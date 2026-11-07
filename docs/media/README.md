# README 動畫素材

首頁的 GIF 轉製自專案既有的 `Resources/Companion/companion-resting.mov` 與 `companion-charging.mov`。
保留原始 152 × 160 像素、6 秒循環，轉為 10 fps、80 色；兩個檔案合計約 700 KiB。
這些是內建角色動畫，不是即時電量或操作錄影。

在儲存庫根目錄安裝 FFmpeg 後，可重新產生：

```bash
for state in resting charging; do
  ffmpeg -v error -i "Resources/Companion/companion-$state.mov" \
    -vf 'fps=10,split[a][b];[a]palettegen=max_colors=80[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
    -loop 0 -y "docs/media/companion-$state.gif"
done
```

貓咪照片與動畫的著作權屬於各原權利人，適用根目錄 [LICENSE](../../LICENSE) 第 5 條；轉檔不改變授權。
