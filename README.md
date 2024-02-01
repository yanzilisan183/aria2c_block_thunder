** 水平一般，能力有限，热爱开源，鄙视吸血行为 **

linux shell bash 脚本，弥补aria2无法反迅雷吸血的弱点。

间隔向JSONRPC请求Peers，并找出迅雷系客户端，将其IP地址通过ipables进行封禁。

定时清理过期的iptables规则，避免产生垃圾记录影响系统性能。

依赖curl, jq, iptables, iptables-save

需要以root身份运行（因iptables和iptables-save需要）

脚本内通过sleep延时循环，不必使用cron定时

更多信息可使用--help参数查看

aria2c_block_thunder.sh --help
