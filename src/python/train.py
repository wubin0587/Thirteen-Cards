"""
train.py
--------
训练总入口。

职责：
  - 训练循环（监督学习：KL 散度 loss 对软标签）
  - 验证循环
  - Checkpoint 保存（.pt）
  - ONNX 导出（供 Unity Sentis 读取）
  - model_config.json 写出
  - 唯一可以写入 src/models/ 目录的模块

用法：
  # 仅生成数据
  python train.py --generate --n_hands 50000 --mc_samples 200

  # 训练（假设数据已生成）
  python train.py --train --epochs 50

  # 生成数据 + 训练 + 导出，一步到位
  python train.py --all

  # 仅导出已有 checkpoint
  python train.py --export --ckpt src/models/thirteen_cards_ranker.pt
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import time
from dataclasses import asdict
from typing import Optional

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR

from models import ModelConfig, TransformerRanker
from data import generate_dataset, load_dataset, get_dataloader
from features import MAX_COMBOS, CARD_DIM, COMBO_DIM, MODEL_INPUT_SPEC

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ============================================================
# 路径常量
# ============================================================

MODELS_DIR   = os.path.join("src", "models")
DATA_PATH    = os.path.join(MODELS_DIR, "train_data.npz")
CKPT_PATH    = os.path.join(MODELS_DIR, "thirteen_cards_ranker.pt")
ONNX_PATH    = os.path.join(MODELS_DIR, "thirteen_cards_ranker.onnx")
CONFIG_PATH  = os.path.join(MODELS_DIR, "model_config.json")

os.makedirs(MODELS_DIR, exist_ok=True)


# ============================================================
# 1.  Loss：KL 散度（软标签监督）
# ============================================================

def kl_loss(
    logits:      torch.Tensor,   # (B, K)
    soft_labels: torch.Tensor,   # (B, K)
    combo_mask:  torch.Tensor,   # (B, K)
) -> torch.Tensor:
    """
    KL 散度 loss：鼓励模型输出分布与蒙特卡洛期望分分布对齐。

    padding 位置的 logits 已经被 model 内部设为 -1e9，
    soft_labels 的对应位置应为 0（由 data.py 保证），
    这里额外做 mask 以防万一。
    """
    # 屏蔽 padding
    logits      = logits.masked_fill(combo_mask == 0, -1e9)
    soft_labels = soft_labels * combo_mask
    # 对软标签再次归一化（防止 mask 后和不为1）
    label_sum = soft_labels.sum(dim=-1, keepdim=True).clamp(min=1e-9)
    soft_labels = soft_labels / label_sum

    log_probs = F.log_softmax(logits, dim=-1)   # (B, K)
    # KL(p_target || p_model) = sum(p_target * (log p_target - log p_model))
    # F.kl_div 期望 input=log_probs, target=probs
    loss = F.kl_div(log_probs, soft_labels, reduction="batchmean")
    return loss


# ============================================================
# 2.  单 epoch 训练
# ============================================================

def train_epoch(
    model:     TransformerRanker,
    loader:    torch.utils.data.DataLoader,
    optimizer: torch.optim.Optimizer,
    device:    torch.device,
) -> float:
    model.train()
    total_loss = 0.0
    n_batches  = 0

    for batch in loader:
        hand_tokens, combo_features, combo_mask, soft_labels, _, _ = [
            t.to(device) for t in batch
        ]

        optimizer.zero_grad()
        logits = model(hand_tokens, combo_features, combo_mask)   # (B, K)
        loss   = kl_loss(logits, soft_labels, combo_mask)
        loss.backward()

        nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optimizer.step()

        total_loss += loss.item()
        n_batches  += 1

    return total_loss / max(n_batches, 1)


# ============================================================
# 3.  验证
# ============================================================

@torch.no_grad()
def validate(
    model:   TransformerRanker,
    loader:  torch.utils.data.DataLoader,
    device:  torch.device,
) -> dict:
    """
    返回验证指标：
      - val_loss    : KL 散度
      - top1_acc    : 模型 argmax 与软标签 argmax 一致率
      - top3_acc    : 模型 top-3 中包含软标签 argmax 的比例
    """
    model.eval()
    total_loss  = 0.0
    top1_hits   = 0
    top3_hits   = 0
    n_samples   = 0

    for batch in loader:
        hand_tokens, combo_features, combo_mask, soft_labels, _, _ = [
            t.to(device) for t in batch
        ]
        B = hand_tokens.size(0)

        logits = model(hand_tokens, combo_features, combo_mask)
        loss   = kl_loss(logits, soft_labels, combo_mask)
        total_loss += loss.item()

        # Top-1 accuracy
        pred_top1  = logits.argmax(dim=-1)                       # (B,)
        label_top1 = soft_labels.argmax(dim=-1)                  # (B,)
        top1_hits += (pred_top1 == label_top1).sum().item()

        # Top-3 accuracy
        pred_top3 = logits.topk(min(3, logits.size(-1)), dim=-1).indices  # (B,3)
        for b in range(B):
            if label_top1[b].item() in pred_top3[b].tolist():
                top3_hits += 1

        n_samples += B

    n_batches = len(loader)
    return {
        "val_loss": total_loss / max(n_batches, 1),
        "top1_acc": top1_hits  / max(n_samples, 1),
        "top3_acc": top3_hits  / max(n_samples, 1),
    }


# ============================================================
# 4.  训练主流程
# ============================================================

def train(
    cfg:        ModelConfig = ModelConfig(),
    data_path:  str  = DATA_PATH,
    ckpt_path:  str  = CKPT_PATH,
    epochs:     int  = 50,
    val_ratio:  float = 0.1,
    patience:   int  = 10,   # early stopping
    resume:     bool = False,
) -> TransformerRanker:
    """
    完整训练流程。

    Parameters
    ----------
    cfg        : 模型超参数
    data_path  : 训练数据 .npz 路径
    ckpt_path  : checkpoint 保存路径
    epochs     : 最大训练轮数
    val_ratio  : 验证集比例
    patience   : early stopping 耐心轮数
    resume     : 是否从已有 checkpoint 恢复训练

    Returns
    -------
    TransformerRanker : 训练完成的模型
    """
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logger.info(f"使用设备: {device}")

    # ---- 数据 ----
    dataset = load_dataset(data_path)
    train_ds, val_ds = dataset.split(val_ratio)
    train_loader = get_dataloader(train_ds, cfg.batch_size, shuffle=True)
    val_loader   = get_dataloader(val_ds,   cfg.batch_size, shuffle=False)
    logger.info(f"训练集: {len(train_ds)} 条，验证集: {len(val_ds)} 条")

    # ---- 模型 ----
    model = TransformerRanker(cfg).to(device)
    logger.info(f"模型参数量: {model.count_parameters():,}")

    # ---- 优化器 ----
    optimizer = AdamW(
        model.parameters(),
        lr=cfg.lr,
        weight_decay=cfg.weight_decay,
    )
    scheduler = CosineAnnealingLR(optimizer, T_max=epochs, eta_min=cfg.lr * 0.01)

    start_epoch = 0
    best_val_loss = float("inf")
    no_improve    = 0

    # ---- 恢复训练 ----
    if resume and os.path.isfile(ckpt_path):
        ckpt = torch.load(ckpt_path, map_location=device)
        model.load_state_dict(ckpt["model_state"])
        optimizer.load_state_dict(ckpt["optimizer_state"])
        start_epoch  = ckpt.get("epoch", 0) + 1
        best_val_loss = ckpt.get("best_val_loss", float("inf"))
        logger.info(f"从 checkpoint 恢复，epoch={start_epoch}")

    # ---- 训练循环 ----
    for epoch in range(start_epoch, epochs):
        t0 = time.time()

        train_loss = train_epoch(model, train_loader, optimizer, device)
        val_metrics = validate(model, val_loader, device)
        scheduler.step()

        elapsed = time.time() - t0
        logger.info(
            f"Epoch {epoch+1:>3}/{epochs} | "
            f"train_loss={train_loss:.4f} | "
            f"val_loss={val_metrics['val_loss']:.4f} | "
            f"top1={val_metrics['top1_acc']*100:.1f}% | "
            f"top3={val_metrics['top3_acc']*100:.1f}% | "
            f"{elapsed:.1f}s"
        )

        # ---- checkpoint ----
        val_loss = val_metrics["val_loss"]
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            no_improve    = 0
            torch.save(
                {
                    "epoch":           epoch,
                    "model_state":     model.state_dict(),
                    "optimizer_state": optimizer.state_dict(),
                    "best_val_loss":   best_val_loss,
                    "cfg":             asdict(cfg),
                    "val_metrics":     val_metrics,
                },
                ckpt_path,
            )
            logger.info(f"  ✓ 新最优 checkpoint 已保存 (val_loss={val_loss:.4f})")
        else:
            no_improve += 1
            if no_improve >= patience:
                logger.info(f"Early stopping at epoch {epoch+1}")
                break

    # 加载最优权重
    if os.path.isfile(ckpt_path):
        ckpt = torch.load(ckpt_path, map_location=device)
        model.load_state_dict(ckpt["model_state"])
        logger.info("最优 checkpoint 已加载")

    return model


# ============================================================
# 5.  ONNX 导出
# ============================================================

def export_onnx(
    model:     TransformerRanker,
    onnx_path: str = ONNX_PATH,
    cfg:       ModelConfig = ModelConfig(),
) -> None:
    """
    将模型导出为 ONNX 格式，供 Unity Sentis 加载。

    输入节点名称与 MODEL_INPUT_SPEC 完全对齐：
      - hand_tokens:    (1, 13, CARD_DIM)
      - combo_features: (1, MAX_COMBOS, COMBO_DIM)
      - combo_mask:     (1, MAX_COMBOS)

    输出节点：
      - logits:         (1, MAX_COMBOS)
    """
    model.eval()
    device = next(model.parameters()).device

    # 构造 dummy 输入
    dummy_hand    = torch.zeros(1, 13, cfg.card_dim,  device=device)
    dummy_combos  = torch.zeros(1, cfg.max_combos, cfg.combo_dim, device=device)
    dummy_mask    = torch.ones(1,  cfg.max_combos,  device=device)

    torch.onnx.export(
        model,
        (dummy_hand, dummy_combos, dummy_mask),
        onnx_path,
        input_names  = ["hand_tokens", "combo_features", "combo_mask"],
        output_names = ["logits"],
        dynamic_axes = {
            "hand_tokens":    {0: "batch"},
            "combo_features": {0: "batch"},
            "combo_mask":     {0: "batch"},
            "logits":         {0: "batch"},
        },
        opset_version    = 17,
        do_constant_folding = True,
        export_params    = True,
        verbose          = False,
    )
    logger.info(f"ONNX 模型已导出至 {onnx_path}")


def save_model_config(cfg: ModelConfig, path: str = CONFIG_PATH) -> None:
    """将 ModelConfig 序列化为 JSON，供 Unity 端对齐输入维度。"""
    payload = {
        "model_config":    asdict(cfg),
        "input_spec":      MODEL_INPUT_SPEC,
        "difficulty_presets": {
            "easy":   {"temperature": 3.0, "aggression": -0.3},
            "medium": {"temperature": 1.5, "aggression":  0.0},
            "hard":   {"temperature": 0.5, "aggression":  0.3},
            "expert": {"temperature": 0.1, "aggression":  0.5},
        },
        "card_dim":   CARD_DIM,
        "combo_dim":  COMBO_DIM,
        "max_combos": MAX_COMBOS,
        "version":    "1.0.0",
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    logger.info(f"模型配置已写入 {path}")


# ============================================================
# 6.  CLI 入口
# ============================================================

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="福建十三水 AI 训练脚本"
    )
    parser.add_argument("--generate",   action="store_true", help="生成训练数据")
    parser.add_argument("--train",      action="store_true", help="训练模型")
    parser.add_argument("--export",     action="store_true", help="导出 ONNX")
    parser.add_argument("--all",        action="store_true", help="生成+训练+导出")
    parser.add_argument("--resume",     action="store_true", help="从 checkpoint 恢复训练")

    # 数据生成参数
    parser.add_argument("--n_hands",    type=int,   default=50_000)
    parser.add_argument("--mc_samples", type=int,   default=200)
    parser.add_argument("--max_k",      type=int,   default=32)
    parser.add_argument("--n_players",  type=int,   default=3)
    parser.add_argument("--seed",       type=int,   default=42)

    # 训练参数
    parser.add_argument("--epochs",     type=int,   default=50)
    parser.add_argument("--lr",         type=float, default=3e-4)
    parser.add_argument("--batch_size", type=int,   default=256)
    parser.add_argument("--d_model",    type=int,   default=64)
    parser.add_argument("--n_layers",   type=int,   default=2)
    parser.add_argument("--patience",   type=int,   default=10)

    # 路径
    parser.add_argument("--data_path",  type=str,   default=DATA_PATH)
    parser.add_argument("--ckpt",       type=str,   default=CKPT_PATH)
    parser.add_argument("--onnx_path",  type=str,   default=ONNX_PATH)

    return parser.parse_args()


def main() -> None:
    args = _parse_args()

    do_generate = args.generate or args.all
    do_train    = args.train    or args.all
    do_export   = args.export   or args.all

    if not any([do_generate, do_train, do_export]):
        logger.warning("未指定操作，请使用 --generate / --train / --export / --all")
        return

    cfg = ModelConfig(
        d_model    = args.d_model,
        n_layers   = args.n_layers,
        lr         = args.lr,
        batch_size = args.batch_size,
    )

    # ---- 生成数据 ----
    if do_generate:
        generate_dataset(
            n_hands    = args.n_hands,
            mc_samples = args.mc_samples,
            max_k      = args.max_k,
            n_players  = args.n_players,
            save_path  = args.data_path,
            seed       = args.seed,
        )

    # ---- 训练 ----
    model = None
    if do_train:
        model = train(
            cfg        = cfg,
            data_path  = args.data_path,
            ckpt_path  = args.ckpt,
            epochs     = args.epochs,
            patience   = args.patience,
            resume     = args.resume,
        )

    # ---- 导出 ----
    if do_export:
        if model is None:
            # 从 checkpoint 加载模型
            if not os.path.isfile(args.ckpt):
                raise FileNotFoundError(
                    f"找不到 checkpoint: {args.ckpt}，请先训练或指定正确路径"
                )
            ckpt = torch.load(args.ckpt, map_location="cpu")
            ckpt_cfg_dict = ckpt.get("cfg", {})
            # 用 checkpoint 中保存的 cfg 重建模型
            cfg = ModelConfig(**{
                k: ckpt_cfg_dict[k]
                for k in ModelConfig.__dataclass_fields__
                if k in ckpt_cfg_dict
            })
            model = TransformerRanker(cfg)
            model.load_state_dict(ckpt["model_state"])

        export_onnx(model, onnx_path=args.onnx_path, cfg=cfg)
        save_model_config(cfg, path=CONFIG_PATH)


if __name__ == "__main__":
    main()
