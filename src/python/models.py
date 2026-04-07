"""
models.py  (RL版本)
-------------------
在原 TransformerRanker 基础上增加：
  - ValueHead：输出标量状态价值 V(s)，供 PPO critic 使用
  - ActorCritic：统一 forward，同时输出 logits(actor) 和 value(critic)
  - inference()：保持兼容，用于推理阶段（不需要 value）

原有 TransformerRanker 保持不变，ActorCritic 继承并扩展。
ONNX 导出仍只导出 actor 部分（TransformerRanker），Unity 端无感知。
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import torch
import torch.nn as nn
import torch.nn.functional as F

from features import CARD_DIM, COMBO_DIM, MAX_COMBOS


# ============================================================
# 1.  超参数配置（扩展 RL 参数）
# ============================================================

@dataclass
class ModelConfig:
    d_model:     int = 64
    n_heads:     int = 4
    n_layers:    int = 2
    d_ffn:       int = 128
    dropout:     float = 0.1

    card_dim:    int = CARD_DIM
    combo_dim:   int = COMBO_DIM
    max_combos:  int = MAX_COMBOS

    # 监督学习参数（保留兼容）
    lr:          float = 3e-4
    weight_decay: float = 1e-4
    batch_size:  int = 256

    # RL 参数
    lr_actor:    float = 3e-4
    lr_critic:   float = 1e-3
    clip_eps:    float = 0.2      # PPO clip
    entropy_coef: float = 0.01   # 熵正则，防止策略过早收敛
    value_coef:  float = 0.5     # critic loss 权重
    gae_lambda:  float = 0.95    # GAE λ
    gamma:       float = 0.99    # 折扣因子（单步博弈设为1.0更合适）
    ppo_epochs:  int = 4         # 每批数据的 PPO 更新轮数
    minibatch_size: int = 64


# ============================================================
# 2.  位置编码
# ============================================================

class LearnedPositionalEncoding(nn.Module):
    def __init__(self, seq_len: int, d_model: int):
        super().__init__()
        self.pe = nn.Embedding(seq_len, d_model)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        pos = torch.arange(x.size(1), device=x.device)
        return x + self.pe(pos).unsqueeze(0)


# ============================================================
# 3.  手牌编码器
# ============================================================

class HandEncoder(nn.Module):
    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.proj = nn.Linear(cfg.card_dim, cfg.d_model)
        self.pos_enc = LearnedPositionalEncoding(13, cfg.d_model)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=cfg.d_model, nhead=cfg.n_heads,
            dim_feedforward=cfg.d_ffn, dropout=cfg.dropout,
            batch_first=True, norm_first=True,
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=cfg.n_layers)
        self.norm = nn.LayerNorm(cfg.d_model)

    def forward(self, hand_tokens: torch.Tensor) -> torch.Tensor:
        x = self.proj(hand_tokens)
        x = self.pos_enc(x)
        x = self.encoder(x)
        return self.norm(x).mean(dim=1)


# ============================================================
# 4.  Combo 编码器
# ============================================================

class ComboEncoder(nn.Module):
    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(cfg.combo_dim, cfg.d_model * 2),
            nn.GELU(),
            nn.Dropout(cfg.dropout),
            nn.Linear(cfg.d_model * 2, cfg.d_model),
            nn.LayerNorm(cfg.d_model),
        )

    def forward(self, combo_features: torch.Tensor) -> torch.Tensor:
        return self.net(combo_features)


# ============================================================
# 5.  交叉注意力打分头（Actor）
# ============================================================

class CrossAttentionScorer(nn.Module):
    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.scale = math.sqrt(cfg.d_model)
        self.q_proj  = nn.Linear(cfg.d_model, cfg.d_model)
        self.k_proj  = nn.Linear(cfg.d_model, cfg.d_model)
        self.v_proj  = nn.Linear(cfg.d_model, cfg.d_model)
        self.out_proj = nn.Linear(cfg.d_model, 1)

    def forward(
        self,
        hand_emb:   torch.Tensor,
        combo_emb:  torch.Tensor,
        combo_mask: torch.Tensor,
    ) -> torch.Tensor:
        q = self.q_proj(hand_emb).unsqueeze(1)
        k = self.k_proj(combo_emb)
        v = self.v_proj(combo_emb)
        attn = torch.bmm(q, k.transpose(1, 2)) / self.scale
        mask_expanded = (1.0 - combo_mask).unsqueeze(1) * -1e9
        attn = torch.softmax(attn + mask_expanded, dim=-1)
        context = torch.bmm(attn, v).squeeze(1)
        combined = combo_emb + context.unsqueeze(1)
        logits = self.out_proj(combined).squeeze(-1)
        logits = logits * combo_mask + (combo_mask - 1.0) * 1e9
        return logits


# ============================================================
# 6.  价值头（Critic）
# ============================================================

class ValueHead(nn.Module):
    """
    将手牌嵌入 → 标量状态价值。
    输入：hand_emb (B, d_model)
    输出：value   (B,)
    """
    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(cfg.d_model, cfg.d_model),
            nn.GELU(),
            nn.Linear(cfg.d_model, 1),
        )

    def forward(self, hand_emb: torch.Tensor) -> torch.Tensor:
        return self.net(hand_emb).squeeze(-1)


# ============================================================
# 7.  TransformerRanker（Actor-only，兼容 ONNX 导出）
# ============================================================

class TransformerRanker(nn.Module):
    """
    纯 Actor，输出各 combo 的 logit。
    ONNX 导出此类，Unity Sentis 使用。
    """
    def __init__(self, cfg: ModelConfig = ModelConfig()):
        super().__init__()
        self.cfg = cfg
        self.hand_encoder  = HandEncoder(cfg)
        self.combo_encoder = ComboEncoder(cfg)
        self.scorer        = CrossAttentionScorer(cfg)

    def forward(
        self,
        hand_tokens:    torch.Tensor,
        combo_features: torch.Tensor,
        combo_mask:     torch.Tensor,
    ) -> torch.Tensor:
        hand_emb  = self.hand_encoder(hand_tokens)
        combo_emb = self.combo_encoder(combo_features)
        return self.scorer(hand_emb, combo_emb, combo_mask)

    def count_parameters(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ============================================================
# 8.  ActorCritic（RL 训练使用）
# ============================================================

class ActorCritic(nn.Module):
    """
    Actor-Critic 统一模型，用于 PPO 训练。

    Actor 部分 = TransformerRanker（可直接导出 ONNX）
    Critic 部分 = ValueHead（仅训练时使用，不导出）

    参数共享：所有 n_players 个 agent 共用同一个 ActorCritic 实例。
    这等价于 MAPPO 的 centralized critic 简化版（此处 critic 仍只看自己手牌）。
    """
    def __init__(self, cfg: ModelConfig = ModelConfig()):
        super().__init__()
        self.cfg = cfg
        self.hand_encoder  = HandEncoder(cfg)
        self.combo_encoder = ComboEncoder(cfg)
        self.scorer        = CrossAttentionScorer(cfg)
        self.value_head    = ValueHead(cfg)

    def forward(
        self,
        hand_tokens:    torch.Tensor,   # (B, 13, CARD_DIM)
        combo_features: torch.Tensor,   # (B, K, COMBO_DIM)
        combo_mask:     torch.Tensor,   # (B, K)
    ) -> tuple[torch.Tensor, torch.Tensor]:
        """
        返回 (logits, value)
          logits : (B, K)  actor 输出
          value  : (B,)    critic 输出
        """
        hand_emb  = self.hand_encoder(hand_tokens)
        combo_emb = self.combo_encoder(combo_features)
        logits    = self.scorer(hand_emb, combo_emb, combo_mask)
        value     = self.value_head(hand_emb)
        return logits, value

    def get_actor(self) -> TransformerRanker:
        """提取 actor 部分，用于 ONNX 导出。"""
        ranker = TransformerRanker(self.cfg)
        ranker.hand_encoder.load_state_dict(self.hand_encoder.state_dict())
        ranker.combo_encoder.load_state_dict(self.combo_encoder.state_dict())
        ranker.scorer.load_state_dict(self.scorer.state_dict())
        return ranker

    def count_parameters(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ============================================================
# 9.  推理接口（兼容原 individual.py）
# ============================================================

def inference(
    model:          TransformerRanker,
    hand_tokens:    torch.Tensor,
    combo_features: torch.Tensor,
    combo_mask:     torch.Tensor,
    temperature:    float = 1.0,
    aggression:     float = 0.0,
    attack_potentials:   torch.Tensor | None = None,
    defense_stabilities: torch.Tensor | None = None,
    deterministic:  bool = False,
) -> int:
    model.eval()
    with torch.no_grad():
        if isinstance(model, ActorCritic):
            logits, _ = model(hand_tokens, combo_features, combo_mask)
        else:
            logits = model(hand_tokens, combo_features, combo_mask)

        logits = logits.squeeze(0)
        mask   = combo_mask.squeeze(0)

        if aggression != 0.0:
            if aggression > 0.0 and attack_potentials is not None:
                logits = logits + aggression * attack_potentials.squeeze(0)
            elif aggression < 0.0 and defense_stabilities is not None:
                logits = logits + (-aggression) * defense_stabilities.squeeze(0)

        logits = logits.masked_fill(mask == 0, float('-inf'))

        if deterministic:
            return int(logits.argmax().item())

        temperature = max(temperature, 1e-3)
        probs = F.softmax(logits / temperature, dim=-1)
        if torch.isnan(probs).any():
            valid_idx = (mask == 1).nonzero(as_tuple=True)[0]
            return int(valid_idx[0].item())
        return int(torch.multinomial(probs, num_samples=1).item())


# ============================================================
# 10.  难度预设
# ============================================================

DIFFICULTY_PRESETS = {
    "easy":   {"temperature": 3.0, "aggression": -0.3},
    "medium": {"temperature": 1.5, "aggression":  0.0},
    "hard":   {"temperature": 0.5, "aggression":  0.3},
    "expert": {"temperature": 0.1, "aggression":  0.5},
}

def get_preset(difficulty: str) -> dict:
    key = difficulty.lower()
    if key not in DIFFICULTY_PRESETS:
        raise ValueError(f"未知难度 '{difficulty}'，可选: {list(DIFFICULTY_PRESETS.keys())}")
    return dict(DIFFICULTY_PRESETS[key])
