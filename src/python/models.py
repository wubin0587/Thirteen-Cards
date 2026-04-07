"""
models.py
---------
模型定义层。

职责：
  - 定义 ModelConfig 超参数数据类
  - 定义 TransformerRanker 网络结构
  - 提供 inference() 推理接口（接受特征张量，返回 logits）
  - 不做任何 IO（存取文件由 train.py 负责）

网络结构概述：
  手牌分支：
    Linear(CARD_DIM→d_model) → Transformer Encoder(L层) → mean pooling → hand_emb

  Combo分支（每个候选独立编码）：
    Linear(COMBO_DIM→d_model) → combo_emb

  交叉注意力打分：
    CrossAttention(query=combo_emb, key/value=hand_emb) → scoring_head → logit

  最终输出：
    shape (batch, MAX_COMBOS)  ← 每个候选的原始 logit（未归一化）

参数量估算（默认配置）：
  d_model=64, n_heads=4, n_layers=2 → ~115K 参数 → ~0.5MB ONNX
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import torch
import torch.nn as nn
import torch.nn.functional as F

from features import CARD_DIM, COMBO_DIM, MAX_COMBOS


# ============================================================
# 1.  超参数配置
# ============================================================

@dataclass
class ModelConfig:
    # 网络维度
    d_model:     int = 64     # Transformer 隐藏维度
    n_heads:     int = 4      # 多头注意力头数
    n_layers:    int = 2      # Transformer Encoder 层数
    d_ffn:       int = 128    # FFN 中间维度（通常 = 2×d_model）
    dropout:     float = 0.1

    # 输入维度（与 features.py 保持一致，勿修改）
    card_dim:    int = CARD_DIM    # 17
    combo_dim:   int = COMBO_DIM   # 74
    max_combos:  int = MAX_COMBOS  # 128

    # 训练相关（仅供 train.py 读取）
    lr:          float = 3e-4
    weight_decay: float = 1e-4
    batch_size:  int = 256


# ============================================================
# 2.  位置编码（可学习，适合短序列）
# ============================================================

class LearnedPositionalEncoding(nn.Module):
    """13个位置的可学习位置编码。"""

    def __init__(self, seq_len: int, d_model: int):
        super().__init__()
        self.pe = nn.Embedding(seq_len, d_model)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (batch, seq, d_model)
        seq = x.size(1)
        pos = torch.arange(seq, device=x.device)
        return x + self.pe(pos).unsqueeze(0)


# ============================================================
# 3.  手牌 Transformer Encoder
# ============================================================

class HandEncoder(nn.Module):
    """
    将 13 张手牌的 token 序列编码为固定维度的上下文向量。

    输入：(batch, 13, CARD_DIM)
    输出：(batch, d_model)  ← mean pooling
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.proj = nn.Linear(cfg.card_dim, cfg.d_model)
        self.pos_enc = LearnedPositionalEncoding(13, cfg.d_model)

        encoder_layer = nn.TransformerEncoderLayer(
            d_model=cfg.d_model,
            nhead=cfg.n_heads,
            dim_feedforward=cfg.d_ffn,
            dropout=cfg.dropout,
            batch_first=True,
            norm_first=True,   # Pre-LN 更稳定
        )
        self.encoder = nn.TransformerEncoder(
            encoder_layer,
            num_layers=cfg.n_layers,
        )
        self.norm = nn.LayerNorm(cfg.d_model)

    def forward(self, hand_tokens: torch.Tensor) -> torch.Tensor:
        # hand_tokens: (B, 13, CARD_DIM)
        x = self.proj(hand_tokens)       # (B, 13, d_model)
        x = self.pos_enc(x)
        x = self.encoder(x)              # (B, 13, d_model)
        x = self.norm(x)
        hand_emb = x.mean(dim=1)         # (B, d_model) — mean pooling
        return hand_emb


# ============================================================
# 4.  Combo 编码器
# ============================================================

class ComboEncoder(nn.Module):
    """
    将每个候选 combo 的特征向量映射到 d_model 维。

    输入：(batch, K, COMBO_DIM)
    输出：(batch, K, d_model)
    """

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
        # combo_features: (B, K, COMBO_DIM)
        return self.net(combo_features)  # (B, K, d_model)


# ============================================================
# 5.  交叉注意力打分头
# ============================================================

class CrossAttentionScorer(nn.Module):
    """
    用手牌上下文向量对每个 combo 进行打分。

    手牌 emb 作为 query，combo emb 作为 key/value，
    输出每个 combo 的标量 logit。

    输入：
      hand_emb:   (B, d_model)
      combo_emb:  (B, K, d_model)
    输出：
      logits:     (B, K)
    """

    def __init__(self, cfg: ModelConfig):
        super().__init__()
        self.d_model = cfg.d_model
        self.q_proj = nn.Linear(cfg.d_model, cfg.d_model)
        self.k_proj = nn.Linear(cfg.d_model, cfg.d_model)
        self.v_proj = nn.Linear(cfg.d_model, cfg.d_model)
        self.out_proj = nn.Linear(cfg.d_model, 1)
        self.scale = math.sqrt(cfg.d_model)

    def forward(
        self,
        hand_emb: torch.Tensor,    # (B, d_model)
        combo_emb: torch.Tensor,   # (B, K, d_model)
        combo_mask: torch.Tensor,  # (B, K)  float32, 1=valid 0=padding
    ) -> torch.Tensor:
        # query: (B, 1, d_model)
        q = self.q_proj(hand_emb).unsqueeze(1)
        # key/value: (B, K, d_model)
        k = self.k_proj(combo_emb)
        v = self.v_proj(combo_emb)

        # Attention weights: (B, 1, K)
        attn = torch.bmm(q, k.transpose(1, 2)) / self.scale

        # Mask padding combos（置为极大负数）
        mask_expanded = (1.0 - combo_mask).unsqueeze(1) * -1e9  # (B,1,K)
        attn = attn + mask_expanded
        attn = torch.softmax(attn, dim=-1)  # (B, 1, K)

        # Context: (B, 1, d_model) → (B, d_model)
        context = torch.bmm(attn, v).squeeze(1)

        # 将 context 与每个 combo_emb 相加后打分
        # combo_emb: (B, K, d_model)，context 广播
        combined = combo_emb + context.unsqueeze(1)  # (B, K, d_model)
        logits = self.out_proj(combined).squeeze(-1)  # (B, K)

        # padding 位置归零（防止采样时被选中）
        logits = logits * combo_mask + (combo_mask - 1.0) * 1e9

        return logits  # (B, K)


# ============================================================
# 6.  完整模型：TransformerRanker
# ============================================================

class TransformerRanker(nn.Module):
    """
    福建十三水理牌 AI 核心模型。

    功能：对 DFS 枚举的 K 个候选 combo 进行排序打分，
    配合温度采样和 aggression 调整选出最终方案。

    输入（均为 float32 张量）：
      hand_tokens:    (B, 13, CARD_DIM)
      combo_features: (B, K, COMBO_DIM)
      combo_mask:     (B, K)

    输出：
      logits: (B, K)  —— 原始得分，越高越倾向于选该 combo
    """

    def __init__(self, cfg: ModelConfig = ModelConfig()):
        super().__init__()
        self.cfg = cfg
        self.hand_encoder   = HandEncoder(cfg)
        self.combo_encoder  = ComboEncoder(cfg)
        self.scorer         = CrossAttentionScorer(cfg)

    def forward(
        self,
        hand_tokens:    torch.Tensor,   # (B, 13, CARD_DIM)
        combo_features: torch.Tensor,   # (B, K, COMBO_DIM)
        combo_mask:     torch.Tensor,   # (B, K)
    ) -> torch.Tensor:
        hand_emb  = self.hand_encoder(hand_tokens)         # (B, d_model)
        combo_emb = self.combo_encoder(combo_features)     # (B, K, d_model)
        logits    = self.scorer(hand_emb, combo_emb, combo_mask)  # (B, K)
        return logits

    def count_parameters(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ============================================================
# 7.  推理接口（含 temperature + aggression 调整）
# ============================================================

def inference(
    model:          TransformerRanker,
    hand_tokens:    torch.Tensor,   # (1, 13, CARD_DIM)
    combo_features: torch.Tensor,   # (1, K, COMBO_DIM)
    combo_mask:     torch.Tensor,   # (1, K)
    temperature:    float = 1.0,
    aggression:     float = 0.0,
    attack_potentials:   torch.Tensor | None = None,  # (1, K)
    defense_stabilities: torch.Tensor | None = None,  # (1, K)
    deterministic:  bool = False,
) -> int:
    """
    执行单次推理，返回选中的 combo 索引。

    Parameters
    ----------
    model            : 已加载的 TransformerRanker
    hand_tokens      : 手牌特征张量
    combo_features   : 候选 combo 特征张量
    combo_mask       : 有效掩码
    temperature      : 采样温度，越小越确定性（0.1~5.0）
    aggression       : 攻守倾向，>0 激进，<0 保守（-1.0~1.0）
    attack_potentials: 每个 combo 的进攻潜力（由 features.py 计算）
    defense_stabilities: 每个 combo 的防守稳定性
    deterministic    : True 时等价于 temperature→0，直接 argmax

    Returns
    -------
    int : 选中的 combo 在 combos 列表中的索引
    """
    model.eval()
    with torch.no_grad():
        logits = model(hand_tokens, combo_features, combo_mask)  # (1, K)
        logits = logits.squeeze(0)   # (K,)
        mask   = combo_mask.squeeze(0)  # (K,)

        # ---- aggression 调整 ----
        if aggression != 0.0:
            if aggression > 0.0 and attack_potentials is not None:
                ap = attack_potentials.squeeze(0)
                logits = logits + aggression * ap
            elif aggression < 0.0 and defense_stabilities is not None:
                ds = defense_stabilities.squeeze(0)
                logits = logits + (-aggression) * ds

        # ---- padding 屏蔽 ----
        logits = logits.masked_fill(mask == 0, float('-inf'))

        if deterministic:
            return int(logits.argmax().item())

        # ---- 温度采样 ----
        temperature = max(temperature, 1e-3)  # 防止除0
        probs = F.softmax(logits / temperature, dim=-1)

        # 替换 NaN（全为 -inf 时的防御）
        if torch.isnan(probs).any():
            valid_idx = (mask == 1).nonzero(as_tuple=True)[0]
            return int(valid_idx[0].item())

        chosen = torch.multinomial(probs, num_samples=1)
        return int(chosen.item())


# ============================================================
# 8.  难度预设
# ============================================================

DIFFICULTY_PRESETS = {
    "easy":   {"temperature": 3.0, "aggression": -0.3},
    "medium": {"temperature": 1.5, "aggression":  0.0},
    "hard":   {"temperature": 0.5, "aggression":  0.3},
    "expert": {"temperature": 0.1, "aggression":  0.5},
}


def get_preset(difficulty: str) -> dict:
    """
    返回预设难度对应的 temperature 和 aggression 参数。

    Parameters
    ----------
    difficulty : str
        "easy" | "medium" | "hard" | "expert"
    """
    key = difficulty.lower()
    if key not in DIFFICULTY_PRESETS:
        raise ValueError(
            f"未知难度 '{difficulty}'，可选: {list(DIFFICULTY_PRESETS.keys())}"
        )
    return dict(DIFFICULTY_PRESETS[key])
