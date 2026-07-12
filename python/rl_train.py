"""
rl_train.py
-----------
强化学习训练主入口：PPO + 课程学习 + 4人自博弈。

算法概述：
  - 策略：参数共享 ActorCritic（所有玩家共用同一网络）
  - 训练算法：PPO-Clip（近端策略优化）
  - 优势估计：GAE（广义优势估计）
  - 多副牌：n_players >= 5 自动切换双副牌，特征编码兼容

课程学习三阶段：
  Phase 1 — "热身"（greedy 对手）
    所有 agent 的对手使用贪心策略（typed_score 最高的合法 combo）。
    目标：让策略快速学会基本的合法理牌，避免倒水。
    退出条件：平均奖励连续 N 局 > threshold_1（例如 > 1.0 水/局）

  Phase 2 — "竞技"（历史 checkpoint pool）
    维护一个旧版本策略池，随机抽取对手。
    目标：防止 self-play 早期的循环博弈；保持策略多样性。
    退出条件：ELO > threshold_2 或训练局数 > phase2_episodes

  Phase 3 — "精炼"（完全 self-play）
    所有 4 个 agent 都使用当前最新策略。
    目标：最终收敛到纳什均衡附近的强策略。
    持续到 max_episodes 结束。

多副牌处理：
  n_players 参数控制副牌数，env.py 自动选 deck_single/deck_double。
  特征编码（encode_hand_multideck）对多副牌同名牌编码相同，
  这意味着模型天然地将同名牌视为等价，符合游戏语义。
  双副牌会出现五同(Five of a Kind)，searchPattern.cpp 已覆盖，
  DFS 候选池会包含五同的 combo，特征维度不变。

Reward shaping：
  - 基础 reward = net_score（C++ closer 结算的净水数）
  - 归一化：除以 max_expected_score（防止梯度爆炸）
  - 倒水惩罚：额外 -5（鼓励合法理牌）
  - 特殊牌型奖励：原分数已包含倍率，无需额外 shaping

用法：
  # 完整训练（推荐）
  python rl_train.py --all

  # 只跑阶段1
  python rl_train.py --phase 1 --episodes 20000

  # 从 checkpoint 继续
  python rl_train.py --resume --ckpt src/models/rl_ranker.pt

  # 多副牌训练（6人双副牌）
  python rl_train.py --n_players 6 --all
"""

from __future__ import annotations

import argparse
import copy
import json
import logging
import math
import os
import random
import time
from collections import deque
from dataclasses import dataclass, asdict, field
from typing import List, Optional, Dict, Tuple, Deque

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.optim import Adam

from env import ThirteenCardsEnv, Observation, greedy_action, assign_positions
from models import ActorCritic, ModelConfig, inference
from features import MAX_COMBOS, CARD_DIM, COMBO_DIM

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR  = os.path.join(_SCRIPT_DIR, "models")
RL_CKPT     = os.path.join(MODELS_DIR, "rl_ranker.pt")
RL_ONNX     = os.path.join(MODELS_DIR, "rl_ranker.onnx")
RL_CFG_JSON = os.path.join(MODELS_DIR, "rl_config.json")
os.makedirs(MODELS_DIR, exist_ok=True)


# ============================================================
# 1.  训练超参数
# ============================================================

@dataclass
class RLConfig:
    n_players:          int   = 4
    max_episodes:       int   = 200_000
    rollout_episodes:   int   = 128    # 每次 PPO 更新前收集的局数

    # 课程学习
    phase1_episodes:    int   = 20_000
    phase2_episodes:    int   = 80_000
    phase1_threshold:   float = 1.0    # 平均净水数超过此值升级 phase
    phase2_elo_thresh:  float = 1200.0
    pool_size:          int   = 10     # checkpoint pool 大小

    # PPO
    ppo_epochs:         int   = 4
    minibatch_size:     int   = 64
    clip_eps:           float = 0.2
    entropy_coef:       float = 0.02
    value_coef:         float = 0.5
    max_grad_norm:      float = 0.5
    gae_lambda:         float = 0.95
    gamma:              float = 1.0   # 单步博弈，不折扣

    # 奖励 shaping
    max_expected_score: float = 20.0  # 归一化分母
    foul_penalty:       float = 5.0   # 倒水额外惩罚

    # 优化器
    lr:                 float = 3e-4
    lr_decay:           float = 0.9999

    # 日志
    log_interval:       int   = 500
    save_interval:      int   = 5000
    eval_interval:      int   = 2000
    eval_episodes:      int   = 200


# ============================================================
# 2.  经验缓冲区（单步博弈）
# ============================================================

@dataclass
class Transition:
    """一个玩家在一局中的完整经验。"""
    hand_tokens:    torch.Tensor   # (13, CARD_DIM)
    combo_features: torch.Tensor   # (MAX_COMBOS, COMBO_DIM)
    combo_mask:     torch.Tensor   # (MAX_COMBOS,)
    action:         int
    log_prob:       float
    value:          float
    reward:         float
    is_special:     bool


class RolloutBuffer:
    """收集多局多玩家的经验，批量转为张量供 PPO 更新。"""

    def __init__(self):
        self._data: List[Transition] = []

    def add(self, t: Transition):
        self._data.append(t)

    def clear(self):
        self._data.clear()

    def __len__(self):
        return len(self._data)

    def to_tensors(self, device: torch.device) -> Dict[str, torch.Tensor]:
        """打包为 PPO 需要的张量字典。"""
        n = len(self._data)
        hand_tokens    = torch.stack([t.hand_tokens    for t in self._data]).to(device)
        combo_features = torch.stack([t.combo_features for t in self._data]).to(device)
        combo_mask     = torch.stack([t.combo_mask     for t in self._data]).to(device)
        actions   = torch.tensor([t.action   for t in self._data], dtype=torch.long,  device=device)
        log_probs = torch.tensor([t.log_prob for t in self._data], dtype=torch.float32, device=device)
        values    = torch.tensor([t.value    for t in self._data], dtype=torch.float32, device=device)
        rewards   = torch.tensor([t.reward   for t in self._data], dtype=torch.float32, device=device)

        # 单步博弈：GAE = reward - value（无时序折扣）
        advantages = rewards - values
        advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)
        returns    = rewards  # 单步 return = reward

        return {
            "hand_tokens":    hand_tokens,
            "combo_features": combo_features,
            "combo_mask":     combo_mask,
            "actions":        actions,
            "old_log_probs":  log_probs,
            "old_values":     values,
            "advantages":     advantages,
            "returns":        returns,
        }


# ============================================================
# 3.  策略采样
# ============================================================

def sample_action(
    model:     ActorCritic,
    obs:       Observation,
    device:    torch.device,
    temperature: float = 1.0,
) -> Tuple[int, float, float]:
    """
    从当前策略采样动作。
    返回 (action_idx, log_prob, value)
    """
    if obs.is_special:
        return 0, 0.0, float(obs.special_score) / 20.0

    hand_tokens    = torch.from_numpy(obs.hand_tokens).unsqueeze(0).to(device)
    combo_features = torch.from_numpy(obs.combo_features).unsqueeze(0).to(device)
    combo_mask     = torch.from_numpy(obs.combo_mask).unsqueeze(0).to(device)

    model.eval()
    with torch.no_grad():
        logits, value = model(hand_tokens, combo_features, combo_mask)

    logits = logits.squeeze(0)
    value  = value.squeeze(0).item()
    mask   = combo_mask.squeeze(0)

    logits = logits.masked_fill(mask == 0, float('-inf'))
    probs  = F.softmax(logits / max(temperature, 1e-3), dim=-1)

    if torch.isnan(probs).any() or obs.n_valid == 0:
        return 0, -math.log(max(obs.n_valid, 1)), value

    dist   = torch.distributions.Categorical(probs)
    action = dist.sample()
    log_prob = dist.log_prob(action).item()
    return int(action.item()), log_prob, value


# ============================================================
# 4.  ELO 评分系统
# ============================================================

class EloSystem:
    def __init__(self, k: float = 32.0, init_rating: float = 1000.0):
        self.k = k
        self.ratings: Dict[str, float] = {}
        self._init = init_rating

    def get(self, name: str) -> float:
        return self.ratings.get(name, self._init)

    def update(self, winner: str, loser: str):
        r_w = self.get(winner)
        r_l = self.get(loser)
        expected_w = 1.0 / (1.0 + 10 ** ((r_l - r_w) / 400.0))
        self.ratings[winner] = r_w + self.k * (1.0 - expected_w)
        self.ratings[loser]  = r_l + self.k * (0.0 - (1.0 - expected_w))


# ============================================================
# 5.  Checkpoint Pool（课程学习阶段2）
# ============================================================

class CheckpointPool:
    """维护历史策略的快照，随机抽取作为对手。"""

    def __init__(self, max_size: int, cfg: ModelConfig, device: torch.device):
        self._pool: Deque[ActorCritic] = deque(maxlen=max_size)
        self._cfg    = cfg
        self._device = device

    def add(self, model: ActorCritic):
        snapshot = ActorCritic(self._cfg).to(self._device)
        snapshot.load_state_dict(copy.deepcopy(model.state_dict()))
        snapshot.eval()
        self._pool.append(snapshot)

    def sample(self) -> Optional[ActorCritic]:
        if not self._pool:
            return None
        return random.choice(list(self._pool))

    def __len__(self):
        return len(self._pool)


# ============================================================
# 6.  PPO 更新
# ============================================================

def ppo_update(
    model:     ActorCritic,
    optimizer: torch.optim.Optimizer,
    batch:     Dict[str, torch.Tensor],
    cfg:       RLConfig,
) -> Dict[str, float]:
    """执行一次 PPO 更新（含多 epoch + minibatch）。"""
    model.train()

    n = batch["actions"].shape[0]
    metrics = {"policy_loss": 0.0, "value_loss": 0.0, "entropy": 0.0, "total_loss": 0.0}
    update_count = 0

    for _ in range(cfg.ppo_epochs):
        # 随机 minibatch
        idx = torch.randperm(n)
        for start in range(0, n, cfg.minibatch_size):
            mb_idx = idx[start: start + cfg.minibatch_size]
            if len(mb_idx) < 4:
                continue

            mb_hand    = batch["hand_tokens"][mb_idx]
            mb_combo   = batch["combo_features"][mb_idx]
            mb_mask    = batch["combo_mask"][mb_idx]
            mb_actions = batch["actions"][mb_idx]
            mb_old_lp  = batch["old_log_probs"][mb_idx]
            mb_adv     = batch["advantages"][mb_idx]
            mb_returns = batch["returns"][mb_idx]

            logits, values = model(mb_hand, mb_combo, mb_mask)

            # Actor loss (PPO-Clip)
            logits_masked = logits.masked_fill(mb_mask == 0, float('-inf'))
            dist   = torch.distributions.Categorical(logits=logits_masked)
            new_lp = dist.log_prob(mb_actions)
            entropy = dist.entropy().mean()

            ratio  = torch.exp(new_lp - mb_old_lp)
            surr1  = ratio * mb_adv
            surr2  = torch.clamp(ratio, 1 - cfg.clip_eps, 1 + cfg.clip_eps) * mb_adv
            policy_loss = -torch.min(surr1, surr2).mean()

            # Critic loss
            value_loss = F.mse_loss(values, mb_returns)

            # 总 loss
            loss = (policy_loss
                    + cfg.value_coef * value_loss
                    - cfg.entropy_coef * entropy)

            optimizer.zero_grad()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), cfg.max_grad_norm)
            optimizer.step()

            metrics["policy_loss"] += policy_loss.item()
            metrics["value_loss"]  += value_loss.item()
            metrics["entropy"]     += entropy.item()
            metrics["total_loss"]  += loss.item()
            update_count += 1

    if update_count > 0:
        for k in metrics:
            metrics[k] /= update_count

    return metrics


# ============================================================
# 7.  Reward shaping
# ============================================================

def shape_reward(
    raw_reward:  float,
    is_foul:     bool,
    is_special:  bool,
    cfg:         RLConfig,
) -> float:
    """归一化 + 倒水惩罚。"""
    reward = raw_reward / cfg.max_expected_score
    if is_foul:
        reward -= cfg.foul_penalty / cfg.max_expected_score
    return float(np.clip(reward, -5.0, 5.0))


# ============================================================
# 8.  单次 rollout（收集一批经验）
# ============================================================

def collect_rollout(
    env:          ThirteenCardsEnv,
    model:        ActorCritic,
    buffer:       RolloutBuffer,
    cfg:          RLConfig,
    device:       torch.device,
    phase:        int,
    pool:         Optional[CheckpointPool],
    temperature:  float = 1.0,
) -> Dict[str, float]:
    """
    收集 cfg.rollout_episodes 局经验。

    phase 1: 所有对手用贪心策略
    phase 2: 随机抽取历史 checkpoint 作对手
    phase 3: 所有 agent 都用当前模型（完全 self-play）
    """
    total_rewards = []
    total_fouls   = 0
    total_episodes = cfg.rollout_episodes

    for _ in range(total_episodes):
        obs_list = env.reset()
        n = env.n_players

        # 决定每个 agent 用什么策略
        actions    = []
        log_probs  = []
        values_    = []
        is_specials = []
        is_fouls   = []

        for i, obs in enumerate(obs_list):
            if i == 0 or phase == 3:
                # 当前模型（agent 0 始终用当前模型，其他在 phase3 也用）
                a, lp, v = sample_action(model, obs, device, temperature)
            elif phase == 1:
                # 贪心对手
                a  = greedy_action(obs)
                lp = 0.0
                v  = 0.0
            else:
                # phase 2: 从 pool 抽取
                opponent = pool.sample() if pool and len(pool) > 0 else None
                if opponent is not None:
                    a, lp, v = sample_action(opponent, obs, device, temperature=1.0)
                else:
                    a = greedy_action(obs)
                    lp, v = 0.0, 0.0

            actions.append(a)
            log_probs.append(lp)
            values_.append(v)
            is_specials.append(obs.is_special)

        _, rewards, done, info = env.step(actions)

        # 判断是否倒水
        for i in range(n):
            obs = obs_list[i]
            if not obs.is_special and obs.n_valid > 0:
                assignment = assign_positions(obs.dfs_result.combos[min(actions[i], obs.n_valid - 1)])
                is_fouls.append(assignment is None)
            else:
                is_fouls.append(False)

        # 只将当前模型的经验（agent 0，或 phase3 全部）存入 buffer
        agents_to_learn = list(range(n)) if phase == 3 else [0]

        for i in agents_to_learn:
            raw_r = rewards[i]
            shaped_r = shape_reward(raw_r, is_fouls[i], is_specials[i], cfg)
            total_rewards.append(shaped_r)

            if not is_specials[i]:
                t = Transition(
                    hand_tokens    = torch.from_numpy(obs_list[i].hand_tokens),
                    combo_features = torch.from_numpy(obs_list[i].combo_features),
                    combo_mask     = torch.from_numpy(obs_list[i].combo_mask),
                    action         = actions[i],
                    log_prob       = log_probs[i],
                    value          = values_[i],
                    reward         = shaped_r,
                    is_special     = False,
                )
                buffer.add(t)

        if is_fouls[0]:
            total_fouls += 1

    return {
        "mean_reward": float(np.mean(total_rewards)) if total_rewards else 0.0,
        "foul_rate":   total_fouls / total_episodes,
    }


# ============================================================
# 9.  评估：当前模型 vs 贪心
# ============================================================

@torch.no_grad()
def evaluate_vs_greedy(
    env:    ThirteenCardsEnv,
    model:  ActorCritic,
    n_eval: int,
    device: torch.device,
) -> Dict[str, float]:
    """模型（seat 0）vs 贪心对手，统计胜率和平均净水数。"""
    model.eval()
    wins = 0
    total_reward = 0.0

    for _ in range(n_eval):
        obs_list = env.reset()
        n = env.n_players
        actions = []
        for i, obs in enumerate(obs_list):
            if i == 0:
                a, _, _ = sample_action(model, obs, device, temperature=0.1)
            else:
                a = greedy_action(obs)
            actions.append(a)
        _, rewards, _, _ = env.step(actions)
        r0 = rewards[0]
        total_reward += r0
        if r0 > 0:
            wins += 1

    return {
        "win_rate":       wins / n_eval,
        "mean_net_score": total_reward / n_eval,
    }


# ============================================================
# 10.  主训练循环
# ============================================================

def train(
    cfg:     RLConfig,
    model_cfg: ModelConfig,
    ckpt_path: str = RL_CKPT,
    resume:    bool = False,
    start_phase: int = 1,
) -> ActorCritic:

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logger.info(f"设备: {device}  玩家数: {cfg.n_players}  "
                f"副牌: {'双副' if cfg.n_players >= 5 else '单副'}")

    model     = ActorCritic(model_cfg).to(device)
    optimizer = Adam(model.parameters(), lr=cfg.lr)
    scheduler = torch.optim.lr_scheduler.ExponentialLR(optimizer, gamma=cfg.lr_decay)

    env  = ThirteenCardsEnv(n_players=cfg.n_players)
    pool = CheckpointPool(cfg.pool_size, model_cfg, device)
    elo  = EloSystem()
    buffer = RolloutBuffer()

    episode       = 0
    phase         = start_phase
    best_win_rate = 0.0
    recent_rewards: Deque[float] = deque(maxlen=500)

    # 恢复 checkpoint
    if resume and os.path.isfile(ckpt_path):
        ckpt = torch.load(ckpt_path, map_location=device)
        model.load_state_dict(ckpt["model_state"])
        optimizer.load_state_dict(ckpt["optimizer_state"])
        episode   = ckpt.get("episode", 0)
        phase     = ckpt.get("phase", 1)
        best_win_rate = ckpt.get("best_win_rate", 0.0)
        logger.info(f"恢复训练: episode={episode}, phase={phase}")

    logger.info(f"开始训练: 共 {cfg.max_episodes} 局, {model.count_parameters():,} 参数")

    # 阶段描述
    phase_names = {1: "热身 (greedy 对手)", 2: "竞技 (checkpoint pool)", 3: "精炼 (full self-play)"}

    t0 = time.time()
    while episode < cfg.max_episodes:

        # ── 阶段切换逻辑 ────────────────────────────────────────
        if phase == 1 and episode >= cfg.phase1_episodes:
            if len(recent_rewards) >= 100:
                avg = np.mean(list(recent_rewards)[-100:])
                if avg > cfg.phase1_threshold or episode >= cfg.phase1_episodes * 1.5:
                    phase = 2
                    pool.add(model)
                    logger.info(f"=== 升级至 Phase 2 (竞技) @ episode {episode} ===")

        if phase == 2 and episode >= cfg.phase1_episodes + cfg.phase2_episodes:
            phase = 3
            logger.info(f"=== 升级至 Phase 3 (精炼) @ episode {episode} ===")

        # ── 计算当前温度（随训练退火）───────────────────────────
        progress = episode / cfg.max_episodes
        temperature = max(0.3, 1.5 * (1.0 - progress))

        # ── 收集 rollout ─────────────────────────────────────────
        buffer.clear()
        rollout_stats = collect_rollout(
            env, model, buffer, cfg, device,
            phase=phase, pool=pool, temperature=temperature,
        )
        episode += cfg.rollout_episodes
        recent_rewards.extend([rollout_stats["mean_reward"]] * cfg.rollout_episodes)

        if len(buffer) < cfg.minibatch_size:
            continue

        # ── PPO 更新 ─────────────────────────────────────────────
        batch   = buffer.to_tensors(device)
        metrics = ppo_update(model, optimizer, batch, cfg)
        scheduler.step()

        # ── 定期加入 pool ─────────────────────────────────────────
        if phase == 2 and episode % (cfg.pool_size * cfg.rollout_episodes) == 0:
            pool.add(model)

        # ── 日志 ─────────────────────────────────────────────────
        if episode % cfg.log_interval < cfg.rollout_episodes:
            elapsed = time.time() - t0
            lr_now  = optimizer.param_groups[0]["lr"]
            logger.info(
                f"[{phase_names[phase]}] ep={episode:>7} | "
                f"r={rollout_stats['mean_reward']:+.3f} | "
                f"foul={rollout_stats['foul_rate']*100:.1f}% | "
                f"π_loss={metrics['policy_loss']:.3f} | "
                f"v_loss={metrics['value_loss']:.3f} | "
                f"ent={metrics['entropy']:.3f} | "
                f"T={temperature:.2f} | lr={lr_now:.2e} | "
                f"{elapsed/60:.1f}min"
            )

        # ── 评估 ─────────────────────────────────────────────────
        if episode % cfg.eval_interval < cfg.rollout_episodes:
            eval_stats = evaluate_vs_greedy(env, model, cfg.eval_episodes, device)
            logger.info(
                f"  [Eval] win_rate={eval_stats['win_rate']*100:.1f}% | "
                f"mean_net={eval_stats['mean_net_score']:+.2f} 水/局"
            )
            if eval_stats["win_rate"] > best_win_rate:
                best_win_rate = eval_stats["win_rate"]
                _save_ckpt(model, optimizer, episode, phase, best_win_rate,
                           ckpt_path, model_cfg, cfg)
                logger.info(f"  ✓ 新最优模型 win_rate={best_win_rate*100:.1f}%")

        # ── 定期保存 ─────────────────────────────────────────────
        if episode % cfg.save_interval < cfg.rollout_episodes:
            _save_ckpt(model, optimizer, episode, phase, best_win_rate,
                       ckpt_path, model_cfg, cfg)

    logger.info(f"训练完成: {episode} 局, 最佳胜率 {best_win_rate*100:.1f}%")
    return model


def _save_ckpt(model, optimizer, episode, phase, best_win_rate,
               path, model_cfg, rl_cfg):
    torch.save({
        "model_state":     model.state_dict(),
        "optimizer_state": optimizer.state_dict(),
        "episode":         episode,
        "phase":           phase,
        "best_win_rate":   best_win_rate,
        "model_cfg":       asdict(model_cfg),
        "rl_cfg":          asdict(rl_cfg),
    }, path)


# ============================================================
# 11.  ONNX 导出
# ============================================================

def export_onnx(
    model:      ActorCritic,
    onnx_path:  str = RL_ONNX,
    cfg:        ModelConfig = ModelConfig(),
) -> None:
    """从 ActorCritic 提取 actor 部分导出 ONNX，供 Unity Sentis 使用。"""
    from train import export_onnx as sl_export_onnx
    actor = model.get_actor()
    actor.eval()
    sl_export_onnx(actor, onnx_path=onnx_path, cfg=cfg)
    logger.info(f"Actor ONNX 已导出: {onnx_path}")


# ============================================================
# 12.  CLI
# ============================================================

def _parse_args():
    p = argparse.ArgumentParser(description="福建十三水 RL 训练")
    p.add_argument("--all",         action="store_true", help="完整训练+导出")
    p.add_argument("--train",       action="store_true")
    p.add_argument("--export",      action="store_true")
    p.add_argument("--resume",      action="store_true")
    p.add_argument("--phase",       type=int, default=1, choices=[1, 2, 3])
    p.add_argument("--n_players",   type=int, default=4)
    p.add_argument("--episodes",    type=int, default=200_000)
    p.add_argument("--rollout",     type=int, default=128)
    p.add_argument("--lr",          type=float, default=3e-4)
    p.add_argument("--d_model",     type=int, default=64)
    p.add_argument("--n_layers",    type=int, default=2)
    p.add_argument("--ckpt",        type=str, default=RL_CKPT)
    p.add_argument("--onnx",        type=str, default=RL_ONNX)
    p.add_argument("--phase1_ep",   type=int, default=20_000)
    p.add_argument("--phase2_ep",   type=int, default=80_000)
    p.add_argument("--entropy",     type=float, default=0.02)
    return p.parse_args()


def main():
    args = _parse_args()

    rl_cfg = RLConfig(
        n_players        = args.n_players,
        max_episodes     = args.episodes,
        rollout_episodes = args.rollout,
        lr               = args.lr,
        entropy_coef     = args.entropy,
        phase1_episodes  = args.phase1_ep,
        phase2_episodes  = args.phase2_ep,
    )
    model_cfg = ModelConfig(
        d_model  = args.d_model,
        n_layers = args.n_layers,
    )

    do_train  = args.train or args.all
    do_export = args.export or args.all

    model = None

    if do_train:
        model = train(
            cfg        = rl_cfg,
            model_cfg  = model_cfg,
            ckpt_path  = args.ckpt,
            resume     = args.resume,
            start_phase = args.phase,
        )

    if do_export:
        if model is None:
            if not os.path.isfile(args.ckpt):
                raise FileNotFoundError(f"找不到 checkpoint: {args.ckpt}")
            device = torch.device("cpu")
            ckpt = torch.load(args.ckpt, map_location=device)
            cfg_d = ckpt.get("model_cfg", {})
            model_cfg = ModelConfig(**{k: cfg_d[k] for k in ModelConfig.__dataclass_fields__ if k in cfg_d})
            model = ActorCritic(model_cfg)
            model.load_state_dict(ckpt["model_state"])
        export_onnx(model, args.onnx, model_cfg)

        cfg_out = {
            "rl_config":   asdict(rl_cfg),
            "model_config": asdict(model_cfg),
        }
        with open(RL_CFG_JSON, "w", encoding="utf-8") as f:
            json.dump(cfg_out, f, indent=2, ensure_ascii=False)
        logger.info(f"配置已写入 {RL_CFG_JSON}")


if __name__ == "__main__":
    main()
