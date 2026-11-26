---
section: Fixed
---

## en

- Clipboard history reads its file off the main thread at launch, so a long history no longer holds up typing; a copy
  made while it is read is kept above the older ones, and the file is never written with only part of the list.

## zh-CN

- 剪贴板历史在启动时不在主线程上读文件，历史很长时也不再卡住打字；读的时候复制的内容排在旧的前面，文件也不会只写进一部分记录。
