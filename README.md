** 水平一般，能力有限，热爱开源，鄙视吸血行为 **

linux shell bash 脚本，弥补aria2无法反迅雷吸血的弱点。

间隔向JSONRPC请求Peers，并找出迅雷系客户端，将其IP地址通过ipables进行封禁。

定时清理过期的iptables规则，避免产生垃圾记录影响系统性能。

依赖curl, jq, iptables, iptables-save

需要以root身份运行（因iptables和iptables-save需要）

脚本内通过sleep延时循环，不必使用cron定时

更多信息可使用--help参数查看

aria2c_block_thunder.sh --help

---

## 开机自启动

在 `/etc/rc.local` 文件中的 `exit 0` 前添加以下内容：

```bash
bash /path/to/aria2c_block_thunder.sh &
```

在aria2未启动时，脚本可能会报错，此时需要先启动aria2，然后再运行脚本。如果aria2本身开机自启，则建议先 sleep 30 秒再运行脚本，确保是在aria2启动后运行脚本。

```bash
sleep 30
bash /path/to/aria2c_block_thunder.sh &
```