#!/bin/bash
# aria2c BT下载防迅雷吸血
# https://github.com/yanzilisan183/aria2c_block_thunder
# Author:           yanzilisan183@sina.com
# LastModifyAt:     15:27 2024-01-24

debug=no                # yes|no，默认no，可通过--debug参数开启
wait_second=60          # 整数，检测间隔时长（单位:秒），可通过--wait参数指定
timeout_second=7200     # 整数，防火墙规则保留时长（单位:秒），可通过--timeout参数指定
rpc_path="http://token:123456@localhost:6800/jsonrpc"   # 默认JSONRPC路径，可通过--rpc-path参数指定

arg_arr=($@)
for (( i=0; i<${#arg_arr[@]}; i++ ))
do
    if [[ "${arg_arr[$i]}" == "-d" || "${arg_arr[$i]}" == "--debug" ]]; then
        debug=yes
    elif [[ "${arg_arr[$i]}" == "-w" || "${arg_arr[$i]}" == "--wait" || "${arg_arr[$i]:0:7}" == "--wait=" ]]; then
        if [[ "${arg_arr[$i]:0:7}" == "--wait=" ]]; then
            wait_second=${arg_arr[$i]:7}
        else
            wait_second=${arg_arr[$(( $i + 1 ))]}
        fi
        wait_second=${wait_second,,}    # 转小写
        if [[ "${wait_second}" =~ ^[0-9]+s?$ ]]; then
            wait_second=${wait_second/s/}
        elif [[ "${wait_second}" =~ ^[0-9]+m?$ ]]; then
            wait_second=${wait_second/m/}
            wait_second=$(( wait_second * 60 ))  # 分转秒
        else
            echo " ${arg_arr[$i]} 需要一个秒(或分钟m)数作为检测间隔参数，当前参数“${wait_second}”不被接受"
            exit 1
        fi
    elif [[ "${arg_arr[$i]}" == "-t" || "${arg_arr[$i]}" == "--timeout" || "${arg_arr[$i]:0:10}" == "--timeout=" ]]; then
        if [[ "${arg_arr[$i]:0:10}" == "--timeout=" ]]; then
            timeout_second=${arg_arr[$i]:10}
        else
            timeout_second=${arg_arr[$(( $i + 1 ))]}
        fi
        timeout_second=${timeout_second,,}    # 转小写
        if [[ "${timeout_second}" =~ ^[0-9]+s?$ ]]; then
            timeout_second=${timeout_second/s/}
        elif [[ "${timeout_second}" =~ ^[0-9]+m$ ]]; then
            timeout_second=${timeout_second/m/}
            timeout_second=$(( timeout_second * 60 ))  # 分转秒
        elif [[ "${timeout_second}" =~ ^[0-9]+h$ ]]; then
            timeout_second=${timeout_second/h/}
            timeout_second=$(( timeout_second * 3600 ))  # 时转秒
        else
            echo " ${arg_arr[$i]} 需要一个秒(或分钟m、小时h)数作为防火墙规则保留时长，当前参数“${timeout_second}”不被接受"
            exit 1
        fi
    elif [[ "${arg_arr[$i]}" == "-p" || "${arg_arr[$i]}" == "--rpc-path" || "${arg_arr[$i]:0:11}" == "--rpc-path=" ]]; then
        if [[ "${arg_arr[$i]:0:11}" == "--rpc-path=" ]]; then
            rpc_path=${arg_arr[$i]:11}
        else
            rpc_path=${arg_arr[$(( $i + 1 ))]}
        fi
        if [[ ! "${rpc_path}" =~ ^(https?|ws)://([^:/@]+:[^:/@]+@)?[^/:@]+(:[0-9]+)?/jsonrpc$ ]]; then
            echo " ${arg_arr[$i]} 需要一个秒(或分钟)数作为检测间隔参数，当前参数“${rpc_path}”不被接受"
            exit 1
        fi
    elif [[ "${arg_arr[$i]}" == "-h" || "${arg_arr[$i]}" == "--help" ]]; then
        echo -e "用法：\n $(basename $0) [选项]...\n"
        echo -e "间隔向JSONRPC请求Peers，并找出迅雷系客户端，将其IP地址通过itables进行封禁。\n"
        echo -e "选项："
        echo "  -p, --rpc-path <RPC-PATH>  JSON-RPC路径，格式“<http|https|ws>://<token:secret|username:passwd>@<host>:<port>/jsonrpc”"
        echo "  -w, --wait <TIME>          指定间隔的时间，默认60秒，可使用后缀s(秒)或m(分钟)，如15s、3m"
        echo "  -t, --timeout <TIME>       指定防火墙规则保留时长，默认2小时，可使用后缀s(秒)、m(分钟)或h(小时)，如7200s、120m、2h"
        echo "  -d, --debug                输出更多信息用于调试"
        echo "  -h, --help                 显示此帮助信息并退出"
        exit 0
    fi
    
done

u=`whoami`
if [ "$u" != "root" ]; then
	echo -e "\033[31m * 请以root身份或前缀sudo执行此脚本\033[0m"
	exit 9
fi
if [[ "`which curl`" == "" ]]; then
	echo -e "\033[31m * 请先安装curl，参考：sudo apt-get install curl\033[0m"
	exit 8
elif [[ "`which jq`" == "" ]]; then
	echo -e "\033[31m * 请先安装jq，参考：sudo apt-get install jq\033[0m"
	exit 8
elif [[ "`which iptables`" == "" || "`which iptables-save`" == "" ]]; then
	echo -e "\033[31m * 请先安装iptables及iptables-save\033[0m"
	exit 8
fi


function debug() {
    if [ "${debug}" == "yes" ]; then
        echo -e "$*"
    fi
}

function urldecode() {
    t_var=$(eval echo \${$1})
    t_var=$(printf $(echo -n $t_var | sed 's/\\/\\\\/g;s/\(%\)\([0-9a-fA-F][0-9a-fA-F]\)/\\x\2/g'))
    eval $1=\$t_var
}

rpc_protocol=${rpc_path%%:*}    # 提取协议
rpc_protocol=${rpc_protocol,,}  # 协议转小写
if [[ "${rpc_protocol}" != "http" && "${rpc_protocol}" != "https" && "${rpc_protocol}" != "ws" ]]; then
    debug "提取JSONRPC PATH中的协议时发生错误"
    exit 2
fi
rpc_tmp=${rpc_path%@*}          # 截取首个@前
if [[ "${rpc_tmp}" != "" ]]; then
    rpc_tmp=${rpc_tmp##*/}      # 截取末个/后
    if [[ ! "${rpc_tmp}" =~ ^[^:/@]+:[^:/@]+$ ]]; then
        debug "提取JSONRPC PATH中的“用户名:密码”或“token:secret”时发生错误"
        exit 2
    else
        rpc_user=${rpc_tmp%:*}  # 提取用户名(当使用-rpc-secret时为token)
        urldecode rpc_user
        rpc_pwd=${rpc_tmp#*:}   # 提取密码(当使用-rpc-secret时为其值)
        urldecode rpc_pwd
    fi
else
    debug "提取JSONRPC PATH中的“用户名:密码”或“token:secret”时发生错误"
    exit 2
fi
rpc_tmp=${rpc_path%/*}          # 截取末个/前(云掉/jsonrpc)
if [[ "${rpc_tmp}" != "" ]]; then
    rpc_tmp=${rpc_tmp//@/\/}    # 替换所有@为/
    rpc_tmp=${rpc_tmp##*/}      # 截取末个/后(截取主机及端口段)
    if [[ "${rpc_tmp}" == "" ]]; then
        debug "提取JSONRPC PATH中的“主机:端口”信息时发生错误"
        exit 2
    elif [[ "${rpc_tmp}" =~ ^[^:]+$ ]]; then
        rpc_host=${rpc_tmp}
        if [[ "${rpc_protocol}" == "http" ]]; then
            rpc_port=80
        elif [[ "${rpc_protocol}" == "https" ]]; then
            rpc_port=443
        else
            debug "提取JSONRPC PATH中的“端口”信息时发生错误"
            exit 2
        fi
    else
        rpc_host=${rpc_tmp%%:*} # 截取首个:前
        rpc_port=${rpc_tmp#*:}  # 截取首个:后
        if [[ ! "${rpc_port}" =~ ^[0-9]+$ ]]; then
            debug "提取JSONRPC PATH中的“端口”信息时发生错误,参考“${rpc_tmp}”"
            exit 2
        fi
    fi
else
    debug "提取JSONRPC PATH中的“主机:端口”信息时发生错误"
    exit 2
fi
debug "\033[33;2m正在使用如下配置运行\n 地址：${rpc_path}\n 协议：${rpc_protocol}\n 主机：${rpc_host}\n 端口：${rpc_port}\n 用户：${rpc_user}\n 口令：${rpc_pwd}\n 间隔：${wait_second}秒\n 超时：${timeout_second}秒\033[0m\n"
t_url="${rpc_protocol}://${rpc_host}:${rpc_port}/jsonrpc"

while [ 1 == 1 ]; do
    t_datetime=`date +"%Y-%m-%d %H:%M:%S"`
    debug "${t_datetime} 开始扫描...."
    # 采集防火墙规则中相关记录
    iptables_rules="`iptables-save -t filter | grep Block_Thunder_`"
    ip6tables_rules="`ip6tables-save -t filter | grep Block_Thunder_`"
    
    t_active=`curl -sk -X POST -H "application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"aria2.tellActive\",\"id\":1,\"params\":[\"${rpc_user}:${rpc_pwd}\"]}" ${t_url}`
    rtn=$?
    if [[ $rtn != 0 ]]; then
        debug "通过RPC请求aria2.tellActive数据时发生错误(curl返回${rtn})"
        exit 3
    elif [[ "`echo "${t_active}" | jq 'has("error")'`" == "true" ]]; then
        debug "通过RPC请求aria2.tellActive数据时发生错误(JSONRPC返回`echo "${t_active}" | jq '.error' -c`)"
        exit 3
    else
        t_gids=`echo "${t_active}" | jq -r ".result[] | .gid"`
    fi

    for gid in ${t_gids}; do
        t_peers=`curl -sk -H "application/json" -X POST -d "{\"jsonrpc\":\"2.0\",\"method\":\"aria2.getPeers\",\"id\":1,\"params\":[\"${rpc_user}:${rpc_pwd}\",\"${gid}\"]}" ${t_url}`
        rtn=$?
        if [[ $rtn != 0 ]]; then
            debug "通过RPC请求aria2.getPeers数据时发生错误(curl返回${rtn})"
            return 3
        elif [[ "`echo "${t_peers}" | jq 'has("error")'`" == "true" ]]; then
            debug "通过RPC请求aria2.getPeers数据时发生错误(JSONRPC返回`echo "${t_peers}" | jq '.error' -c`)"
            exit 3
        else
            t_peerIdips=(`echo "${t_peers}" | jq -r ".result[] | .peerId, .ip"`)   # 通过()采集成数组
        fi
        for (( i=0; i<${#t_peerIdips[@]}; i=`expr $i+2` )); do
            t_peerIdips[$i]=${t_peerIdips[$i]//%2D/-}
            if [ "${debug}" == "yes" ]; then
                printf 'GID:%-18s%-4sIP:%-18speerID:%s\n' ${gid} $(( ($i+2)/2 )) ${t_peerIdips[(( $i + 1 ))]} ${t_peerIdips[$i]}
            fi
            if [[ "${t_peerIdips[$i]}" =~ ^-?SD || "${t_peerIdips[$i]}" =~ ^-?XL ]]; then
                if [[ "`echo ${iptables_rules} | grep \"${t_peerIdips[(( $i + 1 ))]}\"`" == "" ]]; then
                    t_datetime=`date +"%Y-%m-%d %H:%M:%S"`
                    iptables -A INPUT -s ${t_peerIdips[(( $i + 1 ))]}/32 -m comment --comment "Block_Thunder_${t_peerIdips[$i]} @ ${t_datetime}" -j DROP
                    ip6tables -A INPUT -s ${t_peerIdips[(( $i + 1 ))]}/64 -m comment --comment "Block_Thunder_${t_peerIdips[$i]} @ ${t_datetime}" -j DROP
                    debug "\033[31m${t_peerIdips[(( $i + 1 ))]} 经iptables封禁(peerID:${t_peerIdips[$i]})\033[0m"
                fi
            fi
        done
    done
    # 请理过期的防火墙规则
    t_basetamp=$(( `date +%s`-$timeout_second ))
    o_IFS="$IFS"    # 备份系统IFS默认值
    IFS=$'\n'
    for rule in ${iptables_rules}; do
        t_time=${rule##*@}      # 截取最后一个@右侧内容
        t_time=${t_time%%\"*}   # 截取第一个"左侧内容
        t_time=${t_time:1}      # 截掉左侧空格
        t_timestamp=`date -d "${t_time}" +%s`
        if [[ ${t_timestamp} -lt ${t_basetamp} ]]; then
            t_command="iptables -D ${rule:3}"
            eval "${t_command}"
            t_ip=${rule:12}
            t_ip=${t_ip%%/*}
            debug "\033[32m${t_ip} 经iptables封禁(封禁时间:${t_time})\033[0m"
        fi
    done
    for rule in ${ip6tables_rules}; do
        t_time=${rule##*@}      # 截取最后一个@右侧内容
        t_time=${t_time%%\"*}   # 截取第一个"左侧内容
        t_time=${t_time:1}      # 截掉左侧空格
        t_timestamp=`date -d "${t_time}" +%s`
        if [[ ${t_timestamp} -lt ${t_basetamp} ]]; then
            t_command="ip6tables -D ${rule:3}"
            eval "${t_command}"
            t_ip=${rule:12}
            t_ip=${t_ip%%/*}
            debug "\033[32m${t_ip} 经iptables封禁(封禁时间:${t_time})\033[0m"
        fi
    done
    IFS="$o_IFS"    # 还原系统IFS值
    debug " "
    sleep $wait_second
done

# vim:ts=4:expandtab:sts=4:sw=4
