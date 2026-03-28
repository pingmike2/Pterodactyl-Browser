jar融合网站：https://jar.zz.cd  (limimg大佬搭建)

ARGO_AUTH=token CM_PASS=密码 CM_PORT=端口 VNC_RES=720x1280 VNC_DEPTH=24 bash <(curl -Ls https://raw.githubusercontent.com/pingmike2/Pterodactyl-Browser/refs/heads/main/chrome.sh) start

ARGO_AUTH: cf隧道密钥，ey开头
CM_PASS:浏览器密码，自己设定  用户名默认admin
CM_PORT:隧道的http端口，随意填，和cf后台对应

VNC_RES=720x1280  分辨率。非必要不修改，应该只支持标准分辨率
VNC_DEPTH=24      清晰度，默认即可。喜欢折腾也可以改
