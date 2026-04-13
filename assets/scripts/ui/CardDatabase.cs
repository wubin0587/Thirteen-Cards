// Scripts/UI/CardDatabase.cs
// 扑克牌贴图查找单例。Resources/Cards/ 下按命名规则存放 52（或 104）张贴图。
// 命名规则：D2, D3, … DA, C2, … SA（与 input.py card_name() 一致）。

using System.Collections.Generic;
using UnityEngine;

public class CardDatabase : MonoBehaviour
{
    public static CardDatabase Instance { get; private set; }

    [Header("Card Sprite Folder (Resources/Cards/)")]
    [SerializeField] private string _spriteFolderPath = "Cards";

    [Header("Back Face Sprite")]
    [SerializeField] private Sprite _backSprite;

    private Dictionary<int, Sprite> _sprites = new();

    private static readonly string[] RANK_NAMES = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" };
    private static readonly string[] SUIT_NAMES = { "D","C","H","S" };

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);
        LoadAllSprites();
    }

    private void LoadAllSprites()
    {
        for (int id = 0; id < 52; id++)
        {
            int rank = id % 13;
            int suit = id / 13;
            string name = SUIT_NAMES[suit] + RANK_NAMES[rank];
            var sprite = Resources.Load<Sprite>($"{_spriteFolderPath}/{name}");
            if (sprite != null) _sprites[id] = sprite;
            else Debug.LogWarning($"[CardDatabase] Sprite not found: {name}");
        }
        // 双副牌（52~103）复用第一副贴图
        for (int id = 52; id < 104; id++)
            if (_sprites.TryGetValue(id - 52, out var s)) _sprites[id] = s;
    }

    public Sprite GetSprite(int cardId)
    {
        if (_sprites.TryGetValue(cardId, out var sprite)) return sprite;
        return null;
    }

    public Sprite GetBackSprite() => _backSprite;

    public string GetCardName(int cardId, bool zh = false)
    {
        int rank = cardId % 13;
        int suit = (cardId % 52) / 13;
        if (zh)
        {
            string[] zhSuits = { "♦","♣","♥","♠" };
            return zhSuits[suit] + RANK_NAMES[rank];
        }
        return SUIT_NAMES[suit] + RANK_NAMES[rank];
    }
}
