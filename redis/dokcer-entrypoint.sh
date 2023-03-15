#!/bin/sh
set -e

# first arg is `-f` or `--some-option`
# or first arg is `something.conf`
# 是否指定配置文件
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
  set -- redis-server "$@"
fi

# 此外，可能希望避免使用 root 用户去启动服务，从而提高安全性，而在启动服务前还需要以 root 身份执行一些必要的准备工作，最后切换到服务用户身份启动服务。或者除了服务外，其它命令依旧可以使用 root 身份执行，方便调试等。
# 这些准备工作是和容器 CMD 无关的，无论 CMD 为什么，都需要事先进行一个预处理的工作。这种情况下，可以写一个脚本，然后放入 ENTRYPOINT 中去执行，而这个脚本会将接到的参数（也就是 <CMD>）作为命令，在脚本最后执行。比如官方镜像 redis 中就是这么做的：
# https://yeasy.gitbook.io/docker_practice/image/dockerfile/entrypoint

# 如果是 redis-server 的话，则切换到 redis 用户身份启动服务器，否则依旧使用 root 身份执行
# allow the container to be started with `--user`
# "$(id -u)" = '0' 判断当前是不是 root 用户, root 用户的 uid 就是 0
if [ "$1" = 'redis-server' -a "$(id -u)" = '0' ]; then
  find . \! -user redis -exec chown redis '{}' +
  # $0 表示当前 shell
  exec su-exec redis "$0" "$@"
fi

# set an appropriate umask (if one isn't set already)
# - https://github.com/docker-library/redis/issues/305
# - https://github.com/redis/redis/blob/bb875603fb7ff3f9d19aad906bd45d7db98d9a39/utils/systemd-redis_server.service#L37
um="$(umask)"
if [ "$um" = '0022' ]; then
  umask 0077
fi

exec "$@"
