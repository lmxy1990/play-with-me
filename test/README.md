# Test 目录

这里放单元测试脚本、测试数据、假对象和 demo 资产。运行时程序逻辑不要依赖本目录；Android/Godot 导出配置会排除 `test/**`。

测试业务功能点时，不要把测试逻辑写回程序目录。需要远程驱动业务流程时，只能通过 debug-only 调试接口调用正常业务逻辑；调试接口默认关闭，并且只能在 debug 包开启。

新增或修复功能点时，同步补充 `test/checks/` 下的脚本。TTS/声音配置相关改动至少覆盖引擎可用性、音色列表、播放 bridge 调用、debug 快照解析和弹窗布局。运行示例：

```powershell
.\tools\run_godot_check.ps1 -Check test\checks\voice_config_page_check.gd,test\checks\android_tts_bridge_check.gd,test\checks\tts_runtime_check.gd
```

Android debug 包部署后，可用 adb 调试脚本读取应用内 TTS runtime、模型资产和本地引擎可用性：

```powershell
.\test\android\tts_debug_snapshot.ps1 -Device <serial>
```

也可以直接用 debug-only 播放 API 验证测试文本是否能走应用内本地推理并完成播放：

```powershell
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine neko_tts -Voice zf_001 -Text "这是调试播放测试文本。"
```

声音配置或本地 TTS 输入处理变更后，必须覆盖中文、数字、小数和英文混合文本，确认不会触发 Kokoro/Sherpa native crash：

```powershell
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine neko_tts -Voice zf_023 -Text "试听开始。你好，今天是 2026 年，座位 3 号。数值 3.14，21 个苹果。字母 A B C，单词 wolf village game。" -WarmUp
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine voxsherpa_tts -Voice zf_024 -Text "这是 VoxSherpa 的调试播放测试，座位 12 号，数值 3.14。" -WarmUp
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine multi_tts -Voice zm_010 -Text "这是 MultiTTS 的调试播放测试，二十一 个苹果，2026 年。" -WarmUp
& "D:\android\platform-tools\adb.exe" -s <serial> logcat -b crash -d -v time
```
