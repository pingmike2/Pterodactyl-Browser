# 🌐 Jar 融合浏览器一键部署教程（优化版）

## 🔗 项目入口
- Jar 融合网站：  
  https://jar.zz.cd （感谢 limimg 大佬搭建）

---

## 🚀 一键启动命令

```bash
ARGO_AUTH=你的Token CM_PASS=你的密码 CM_PORT=端口 \
VNC_RES=720x1280 VNC_DEPTH=24 \
bash <(curl -Ls https://raw.githubusercontent.com/pingmike2/Pterodactyl-Browser/refs/heads/main/chrome.sh) start

```

⚙️ 参数说明

🔐 ARGO_AUTH
	•	Cloudflare Argo Tunnel 密钥
	•	一般以 ey 开头
	•	必填

🔑 CM_PASS
	•	浏览器访问密码（自定义）
	•	默认用户名：admin
	•	建议设置复杂一点

🌍 CM_PORT
	•	HTTP 隧道端口
	•	可随意填写，但必须与 Cloudflare 后台配置一致
	•	示例：8080 / 3000

🖥️ VNC_RES（分辨率）
	•	默认：720x1280（推荐保持）
	•	建议使用标准分辨率，否则可能异常

🎨 VNC_DEPTH（色深）
	•	默认：24
	•	数值越高画质越好，但占用也越高
	•	一般无需修改

💡 使用建议
	•	新手建议直接使用默认参数（只改前三个）
	•	如果连接异常，优先检查：
	•	Argo Token 是否正确
	•	端口是否与 CF 后台一致
	•	分辨率乱改可能导致黑屏或卡盾
