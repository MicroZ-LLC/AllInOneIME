---
section: Fixed
---

## en

- Pinyin starts when two programs set up Rime's folder at the same moment (on a first install, for example, the
  installer's registration and the input method macOS starts for it): one of them could fail to start Rime, and pinyin
  stayed off until the input method restarted. Within the input method Rime starts one caller at a time. The Rime logs
  folder keeps `rime-start.txt`, the steps of the last start, so that a crash in one shows where it stopped (the next
  start says so in the log).

## zh-CN

- 两个程序同时准备 Rime 的文件夹时（例如首次安装时，安装程序的注册步骤和 macOS 为它启动的输入法），拼音也能正常启动：以前其中一个可能无法启动 Rime，拼音在输入法重启前一直不可用。输入法内的 Rime 启动一次只由一个调用者进行。Rime 日志文件夹里会保留 `rime-start.txt`，记录最近一次启动的各个步骤；启动中途崩溃时能看出停在哪一步（下次启动会写进日志）。
