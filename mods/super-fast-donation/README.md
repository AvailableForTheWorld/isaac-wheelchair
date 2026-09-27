# 超级快速捐款 / Super Fast Donation

适用于 The Binding of Isaac: Repentance+ 的快速捐款模组。

## 功能

- 接触普通捐款机或贪婪捐款机时自动加速。
- 每 30 个游戏逻辑帧安排 100 次成功投币，即约每秒 100 次。
- 每次投币后立即退还金币；即使当前为 0 金币，也会在内部临时借用 1 枚硬币完成捐款，帧末不会留下额外金币。
- 普通与贪婪捐款机一旦触发卡币标志，会立即清除标志并只重建对应机器。
- 加速期间锁定玩家和机器的位置，避免额外更新把玩家或机器推走。
- 多人游戏时，每台机器选择正在接触且距离最近的玩家进行加速，并把原生投币退还给实际捐款的玩家。

只有房间处于已清理状态时才会执行额外更新，避免在战斗中加速玩家逻辑。捐款计数达到游戏自身的普通捐款机或贪婪捐款机上限后，游戏不会再接受新的捐款；模组会自动降低重试频率以避免卡顿。

## 兼容性

本模组已经包含快速捐款、免费捐款和防卡币逻辑。请停用同时修改捐款机的模组，例如 Free Donation、No Jam 或为贪婪捐款机开启加速的 TimeMachine，以免重复退款、重复更新或生成额外金币。

## 安装

从仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Mod.ps1 -Mod super-fast-donation
```

然后在 Isaac 的 Mods 菜单中启用 **超级快速捐款 / Super Fast Donation**。

该模组目前是本地包。首次上传 Steam Workshop 后，需要把生成的 Workshop ID 同时写入 `mods.json` 与 `content/metadata.xml`。
