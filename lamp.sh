#!/bin/bash

read -p "请输入新的数据库密码：" -s password



echo '正在配置YUM源...'

\cp Software/CentOS7-Base-163.repo /etc/yum.repos.d/
sed -i 's/\$releasever/7/g' /etc/yum.repos.d/CentOS7-Base-163.repo
sed -i 's/^enabled=.*/enabled=1/g' /etc/yum.repos.d/CentOS7-Base-163.repo


echo '正在安装依赖包...'

yum -y install epel-release vim bzip2 && sleep 1
yum groups mark install 'Development Tools' && sleep 1
yum -y install openssl-devel pcre-devel expat-devel libtool gcc gcc-c++ && sleep 1

yum -y install ncurses-devel openssl-devel openssl cmake mariadb-devel && sleep 1
rpm -Uvh Software/remi-release-7.rpm && sleep 1
yum clean all && sleep 1
yum makecache --enablerepo=remi-php74 && sleep 1
yum -y install libxml2 libxml2-devel openssl openssl-devel bzip2 bzip2-devel libcurl libcurl-devel libicu-devel libjpeg libjpeg-devel libpng libpng-devel openldap-devel  pcre-devel freetype freetype-devel gmp gmp-devel libmcrypt libmcrypt-devel readline readline-devel libxslt libxslt-devel mhash mhash-devel php72-php-mysqlnd && sleep 1

echo '正在解压文件...'
tar xf Software/apr-1.7.0.tar.bz2 -C /usr/src/
tar xf Software/apr-util-1.6.1.tar.bz2 -C /usr/src/
tar xf Software/httpd-2.4.43.tar.bz2 -C /usr/src/

tar xf Software/mysql-5.7.30-linux-glibc2.12-x86_64.tar.gz -C /usr/local/
ln -sv /usr/local/mysql-5.7.30-linux-glibc2.12-x86_64/ /usr/local/mysql
tar xf Software/php-7.2.8.tar.xz -C /usr/src/

# 创建服务用户和组
id apache
if [ $? -ne 0 ];then
    useradd -r -M -s /sbin/nologin apache
fi

id mysql
if [ $? -ne 0 ];then
    useradd -r -M -s /sbin/nologin -u 306 mysql
fi


chown -R mysql.mysql /usr/local/mysql*
echo 'export PATH=/usr/local/mysql/bin:$PATH' > /etc/profile.d/mysql.sh
mkdir /opt/data
chown -R mysql.mysql /opt/data/



echo '正在配置服务...' 

# 配置apache
cd /usr/src/apr-1.7.0/
grep '$RM "$cfgfile"' configure
if [ $? -ne 0 ];then
    sed -i 's/$RM "$cfgfile"/#$RM "$cfgfile"/g' configure
fi
./configure --prefix=/usr/local/apr && make && make install && sleep 1

cd /usr/src/apr-util-1.6.1
./configure --prefix=/usr/local/apr-util --with-apr=/usr/local/apr && make && make install && sleep 1
cd /usr/src/httpd-2.4.43/
./configure --prefix=/usr/local/apache \
--sysconfdir=/etc/httpd24 \
--enable-so \
--enable-ssl \
--enable-cgi \
--enable-rewrite \
--with-zlib \
--with-pcre \
--with-apr=/usr/local/apr \
--with-apr-util=/usr/local/apr-util/ \
--enable-modules=most \
--enable-mpms-shared=all \
--with-mpm=prefork && make && make install && sleep 1

echo 'export PATH=/usr/local/apache/bin:$PATH' > /etc/profile.d/httpd.sh
ln -s /usr/local/apache/include /usr/include/apache
echo 'MANDATORY_MANPATH /usr/local/apache/man' >> /etc/man_db.conf
sed -i '/#ServerName/s/#//g' /etc/httpd24/httpd.conf

# 配置mysql
/usr/local/mysql/bin/mysqld --initialize-insecure --user=mysql --datadir=/opt/data/
ln -s /usr/local/mysql/include /usr/include/mysql
echo 'MANDATORY_MANPATH /usr/local/mysql/man' >> /etc/man_db.conf
echo '/usr/local/mysql/lib' > /etc/ld.so.conf.d/mysql.conf && ldconfig

cat > /etc/my.cnf <<EOF
[mysqld]
basedir = /usr/local/mysql
datadir = /opt/data
socket = /tmp/mysql.sock
port = 3306
pid-file = /opt/data/mysql.pid
user = mysql
skip-name-resolve
EOF

cp -a /usr/local/mysql/support-files/mysql.server /etc/init.d/mysqld
sed -ri 's#^(basedir=).*#\1/usr/local/mysql#g' /etc/init.d/mysqld
sed -ri 's#^(datadir=).*#\1/opt/data#g' /etc/init.d/mysqld

# 配置php
cd /usr/src/php-7.2.8/
./configure --prefix=/usr/local/php7  \
--with-config-file-path=/etc \
--enable-fpm \
--enable-inline-optimization \
--disable-debug \
--disable-rpath \
--enable-shared \
--enable-soap \
--with-openssl \
--enable-bcmath \
--with-iconv \
--with-bz2 \
--enable-calendar \
--with-curl \
--enable-exif  \
--enable-ftp \
--with-gd \
--with-jpeg-dir \
--with-png-dir \
--with-zlib-dir \
--with-freetype-dir \
--with-gettext \
--enable-json \
--enable-mbstring \
--enable-pdo \
--with-mysqli=mysqlnd \
--with-pdo-mysql=mysqlnd \
--with-readline \
--enable-shmop \
--enable-simplexml \
--enable-sockets \
--enable-zip \
--enable-mysqlnd-compression-support \
--with-pear \
--enable-pcntl \
--enable-posix && make && make install && sleep 1

echo 'export PATH=/usr/local/php7/bin/:$PATH' > /etc/profile.d/php.sh
cp php.ini-production /etc/php.ini
cp sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
chmod +x /etc/rc.d/init.d/php-fpm
cp /usr/local/php7/etc/php-fpm.conf.default /usr/local/php7/etc/php-fpm.conf
cp /usr/local/php7/etc/php-fpm.d/www.conf.default /usr/local/php7/etc/php-fpm.d/www.conf

sed -i 's/listen = .*/listen = 0.0.0.0:9000/g' /usr/local/php7/etc/php-fpm.d/www.conf

echo '正在启动服务...'

systemctl stop firewalld
systemctl disable firewalld
sed -ri 's/(SELINUX=).*/\1disabled/g' /etc/selinux/config && getenforce 0

/usr/local/apache/bin/apachectl start

# 设置apache开机自启
cp /usr/local/apache//bin/apachectl /etc/rc.d/init.d/httpd
echo 'chkconfig: 2345 61 39' >> /etc/rc.d/init.d/httpd
chkconfig --add httpd

service mysqld start && sleep 1
chkconfig --add mysqld
/usr/local/mysql/bin/mysql -e "set password = password('$password');"
echo "数据库密码已设置为$password"
service php-fpm start
chkconfig --add php-fpm

＃apache配置

#!/bin/bash

sed -i '/proxy_module/s/#//g' /etc/httpd24/httpd.conf
sed -i '/proxy_fcgi_module/s/#//g' /etc/httpd24/httpd.conf

cat > /usr/local/apache/htdocs/index.php <<EOF
<?php
   phpinfo();
?>
EOF

chown -R apache.apache /usr/local/apache/htdocs/

sed -i '/httpd-vhosts.conf/s/^#// ' /etc/httpd24/httpd.conf
cat > /etc/httpd24/extra/httpd-vhosts.conf <<EOF
<VirtualHost *:80>
    DocumentRoot "/usr/local/apache/htdocs"
    ServerName www.example.com
    ProxyRequests Off
    ProxyPassMatch ^/(.*\.php)$ fcgi://127.0.0.1:9000/usr/local/apache/htdocs/\$1
    <Directory "/usr/local/apache/htdocs">
        Options none
        AllowOverride none
        Require all granted
    </Directory>
</VirtualHost>
EOF

php_st=$(grep 'httpd-php' /etc/httpd24/httpd.conf |wc -l)

if [ $php_st -eq 0 ];then
    sed -i '398a\    AddType application/x-httpd-php-source .phps' /etc/httpd24/httpd.conf
    sed -i '398a\    AddType application/x-httpd-php .php' /etc/httpd24/httpd.conf
fi
index_php=$(grep 'index.php' /etc/httpd24/httpd.conf |wc -l)
if [ $index_php -eq 0 ];then
    sed -i '/    DirectoryIndex/s/index.html/index.php index.html/g' /etc/httpd24/httpd.conf
fi

/usr/local/apache/bin/apachectl stop && sleep 1
/usr/local/apache/bin/apachectl start
