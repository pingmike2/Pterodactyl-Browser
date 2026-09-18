# gbjs.serv00.net 备份（ff_liteh.sh 链路专用）

备份时间：2026-09-18（UTC+8）
来源：ff_liteh.sh 直接引用 + 其调用子文件（cftunnel.sh / runfirefoxh.sh）嵌套引用。

| 备份文件 | 原下载地址 | 说明 |
|---|---|---|
| alpineproot322.sh | https://gbjs.serv00.net/sh/alpineproot322.sh | ff_liteh.sh:53 直接引用 |
| count.sh | https://gbjs.serv00.net/sh/count.sh | ff_liteh.sh:211 直接引用 |
| runfirefoxh.sh | https://gbjs.serv00.net/sh/runfirefoxh.sh | ff_liteh.sh:215 直接引用（与仓库版有差异，差异版一并备份） |
| ps.sh | https://gbjs.serv00.net/sh/ps.sh | 子文件 cftunnel.sh:35 嵌套引用 |
| menuh.xml | https://gbjs.serv00.net/tar/menuh.xml | 子文件 runfirefoxh.sh:138 嵌套引用 |
| ago | https://gbjs.serv00.net/bin/ago | 子文件 cftunnel.sh:25/27 嵌套引用（x86_64） |
| agoarm64 | https://gbjs.serv00.net/bin/agoarm64 | 子文件 cftunnel.sh:25/27 嵌套引用（arm64） |

SHA256：
- alpineproot322.sh: 48a9744ed84e134ef2d46daceea179b21a0c758959c2c8d7502ca31500c6b5d0
- count.sh: 02bf5eab74b6db527f4c71cc114d54782142238739d813d3dce2807b349d1a92
- runfirefoxh.sh: d28391f7fab6b06546262b26792c442236799b93e199ca315e58be8e0c9ab726
- ps.sh: 0638ce24223ba17f4e1e8c6273872b4425d0e783a8ea914b420a23ef6fba2520
- menuh.xml: 40e16c998511c3233dda070bb18aa59b70850612b9dcc50b808f870c9eb76f57
- ago: 922606671bdae94daacca33f8af0abcf7c426e6524921bcce476c8831291fa08
- agoarm64: 449baa3eb07f1ed7541f7a6e8a25bf7822ac1fdb60fbb2ebe9c344b2df20951a

注意：现有代码未改动，仅新增 gbjs_backup/ 目录。
