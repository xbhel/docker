# 基础镜像
FROM alpine:3.17

# 添加一个 redis 用户和组
RUN addgroup -S -g 1000 redis && adduser -S -G redis -u 999 redis
# alpine 已经有一个 999 的组 id, 所以这里使用 1000

# apk 是 alpine 的包管理器
# 使用 apk 包管理器下载 su-exec 等软件，以便 su <user> 进行用户切换
RUN apk add --no-cache \
  # 获取 su-exec 以便从 root 轻松降级
  'su-exec>=0.2' \
  # add tzdata for https://github.com/docker-library/redis/issues/138
  tzdata

# 设置环境变量
ENV REDIS_VERSION 7.0.9
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-7.0.9.tar.gz
ENV REDIS_DOWNLOAD_SHA f77135c2a47c9151d4028bfea3b34470ab4d324d1484f79a84c6f32a3cfb9f65

# set 设置 shell 执行环境; 
# -e: 若指令传回值不等于0，则立即退出shell;
# -u: 当执行时使用到未定义过的变量，则显示错误信息;
# -x 　执行指令后，会先显示该指令及所下的参数;

# 使用 apk 包管理器安装 
# --no-cahe 表示不使用缓存
# --virtual <virtual-package-name> 将依赖不添加未全局包，将包和其依赖项安装到虚拟包 .build-deps 中，以便于使用后进行清理，apk del <virtual-package-name>
# https://stackoverflow.com/questions/46221063/what-is-build-deps-for-apk-add-virtual-command
# 如我需要 gcc 来编译一个程序，但是一旦程序被编译我就不再需要 gcc 了, 这时候我就可以以虚拟包的形式安装 gcc 及其依赖项，并在安装完成后通过 apk del <virtual-package-name> 进行清理。
# RUN apk add --virtual mypacks gcc vim \
# && apk del mypacks

# 安装 gcc、make、wget 等包
RUN set -eux; \
  \
  apk add --no-cache --virtual .build-deps \
  coreutils \
  dpkg-dev dpkg \
  gcc \
  linux-headers \
  make \
  musl-dev \
  openssl-dev \
  # install real "wget" to avoid:
  #   + wget -O redis.tar.gz https://download.redis.io/releases/redis-6.0.6.tar.gz
  #   Connecting to download.redis.io (45.60.121.1:80)
  #   wget: bad header line:     XxhODalH: btu; path=/; Max-Age=900
  wget \
  ; \
  \
  # 下载 redis 
  wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
  # 做 redis 包校验和
  echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
  # 创建解压目录
  mkdir -p /usr/src/redis; \
  # 解压至 /usr/src/redis; --strip-components=1 表示省略解压文件的第一层目录，如原目录为 redis/*, 则输出为 *.
  tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
  # 删除压缩包释放空间
  rm redis.tar.gz; \
  \
  # 禁用保护模式(protected-mode)，在 docker 环境开启保护模式是不必要的
  # 因为 Redis 运行在 Docker 中时，端口是不会自动暴露的，只有当用户明确通过 -p/-P 指定时才会生效。
  # [1]: https://github.com/redis/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
  grep -E '^ *createBoolConfig[(]"protected-mode",.*, *1 *,.*[)],$' /usr/src/redis/src/config.c; \
  sed -ri 's!^( *createBoolConfig[(]"protected-mode",.*, *)1( *,.*[)],)$!\10\2!' /usr/src/redis/src/config.c; \
  grep -E '^ *createBoolConfig[(]"protected-mode",.*, *0 *,.*[)],$' /usr/src/redis/src/config.c; \
  # for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
  # see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
  # (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
  \
  # 设置编译环境，可以不管
  # https://github.com/jemalloc/jemalloc/issues/467 -- we need to patch the "./configure" for the bundled jemalloc to match how Debian compiles, for compatibility
  # (also, we do cross-builds, so we need to embed the appropriate "--build=xxx" values to that "./configure" invocation)
  gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
  extraJemallocConfigureFlags="--build=$gnuArch"; \
  # https://salsa.debian.org/debian/jemalloc/-/blob/c0a88c37a551be7d12e4863435365c9a6a51525f/debian/rules#L8-23
  dpkgArch="$(dpkg --print-architecture)"; \
  case "${dpkgArch##*-}" in \
  amd64 | i386 | x32) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=12" ;; \
  *) extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-page=16" ;; \
  esac; \
  extraJemallocConfigureFlags="$extraJemallocConfigureFlags --with-lg-hugepage=21"; \
  grep -F 'cd jemalloc && ./configure ' /usr/src/redis/deps/Makefile; \
  sed -ri 's!cd jemalloc && ./configure !&'"$extraJemallocConfigureFlags"' !' /usr/src/redis/deps/Makefile; \
  grep -F "cd jemalloc && ./configure $extraJemallocConfigureFlags " /usr/src/redis/deps/Makefile; \
  \
  export BUILD_TLS=yes; \
  # 编译 redis
  make -C /usr/src/redis -j "$(nproc)" all; \
  # 安装，默认安装路径 /usr/local/bin，默认会在 /usr/local/bin 生成 redis-server, redis-cli 等可执行文件。
  # make PREFIX=path install; 可以通过 PREFIX 指定路径
  make -C /usr/src/redis install; \
  \
  # TODO https://github.com/redis/redis/pull/3494 (deduplicate "redis-server" copies)
  # 校验 redis-server 文件
  serverMd5="$(md5sum /usr/local/bin/redis-server | cut -d' ' -f1)"; export serverMd5; \
  find /usr/local/bin/redis* -maxdepth 0 \
  -type f -not -name redis-server \
  -exec sh -eux -c ' \
  md5="$(md5sum "$1" | cut -d" " -f1)"; \
  test "$md5" = "$serverMd5"; \
  ' -- '{}' ';' \
  -exec ln -svfT 'redis-server' '{}' ';' \
  ; \
  \
  # 删除 /usr/src/redis 下的源文件
  rm -r /usr/src/redis; \
  \
  runDeps="$( \
  scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
  | tr ',' '\n' \
  | sort -u \
  | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"; \
  apk add --no-network --virtual .redis-rundeps $runDeps; \
  # 清理 apk 虚拟包
  apk del --no-network .build-deps; \
  \
  # 查看 redis-cli 和 redis-server 版本
  redis-cli --version; \
  redis-server --version

# 创建 redis 数据目录; 并赋予给新建 redis 用户
# 后续我们在配置 redis 时可以将 数据目录，日志目录等都放在这个下面
RUN mkdir /data && chown redis:redis /data
# 声明数据卷
VOLUME /data
# 容器主目录， RUN、CMD、ENTRYPOINT 的工作目录
WORKDIR /data

# 将 docker-entrypoint.sh 拷贝到容器的 /usr/local/bin/ 路径下
COPY docker-entrypoint.sh /usr/local/bin/
# 指定默认的入口命令，该命令会在容器启动时作为根命令执行。
ENTRYPOINT ["docker-entrypoint.sh"]
# 声明暴露的端口
EXPOSE 6379
# 容器启动时默认的执行命令，当指定 ENTRYPOINT 时，命令将作为 ENTRYPOINT 的参数执行。
CMD ["redis-server"]