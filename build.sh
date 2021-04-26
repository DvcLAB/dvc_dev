#1. gitlab
mkdir -p /opt/gitlab/volumes/config && mkdir -p /opt/gitlab/volumes/data && mkdir -p /opt/gitlab/volumes/logs
docker-compose -f /opt/gitlab/gitlab.yaml up -d
wait
#给Keycloak配置反向代理https访问，gitlab oauth必须是https
cat >> /opt/gitlab/volumes/config/gitlab.rb <<EOF
gitlab_rails['omniauth_allow_single_sign_on'] = ['saml','openid_connect']
gitlab_rails['omniauth_block_auto_created_users'] = false
#gitlab_rails['omniauth_auto_link_ldap_user'] = true
gitlab_rails['omniauth_providers'] = [
  { name: 'openid_connect',
      label: 'Keycloak',
      args: {
        name: 'openid_connect',
        scope: ['openid','profile'],
        response_type: 'code',
        issuer: 'https://collaborauth.dvclab.com/auth/realms/412',
        discovery: true,
        client_auth_method: 'query',
        uid_field: 'preferred_username',
        send_scope_to_token_endpoint: false,
        client_options: {
          identifier: 'gitlab',
          secret: 'fd23b094-60e8-4a1a-9f22-fdad0008951a',
          redirect_uri: 'http://192.168.1.240:8000/users/auth/openid_connect/callback'
        }
      }
    }
]
EOF
docker restart gitlab

#2. wikijs 还需UI界面配置2
mkdir -p /opt/wikijs/volumes/config && mkdir -p /opt/wikijs/volumes/data
chown -R 1000:1000 /opt/wikijs/volumes/data
docker-compose -f /opt/wikijs/wikijs.yaml up -d

#3. wordpress  UI界面安装插件配置
mkdir -p /opt/wordpress/volumes/html && mkdir -p /opt/wordpress/volumes/data
docker-compose -f /opt/wordpress/wordpress.yaml up -d 

#4. mattermost  修改config文件开启插件上传 UI界面安装插件配置
mkdir -pv /opt/mattermost/volumes/app/mattermost/{data,logs,config,plugins,client-plugins}
mkdir -pv /opt/mattermost/volumes/db/var/lib/postgresql/data
mkdir -pv /opt/mattermost/volumes/web/cert
chown -R 2000:2000 /opt/mattermost/volumes/app/mattermost/
docker pull mattermost/mattermost-prod-app  \
&& docker pull mattermost/mattermost-prod-db \
&& docker pull mattermost/mattermost-prod-web 
docker-compose -f /opt/mattermost/mattermost.yaml  up -d

#4.1 jitsi 
mkdir -p /opt/jitsi && \
cd /opt/jitsi && \
git clone https://github.com/jitsi/docker-jitsi-meet && cd docker-jitsi-meet && git checkout cb4d9413b7481b9767ff5d2ec09e22bdc76e74e3 &&\
cp env.example .env
#修改.env
cd /opt/jitsi/docker-jitsi-meet && \
./gen-passwords.sh && \
mkdir -p ~/.jitsi-meet-cfg/{web/letsencrypt,transcripts,prosody/config,prosody/prosody-plugins-custom,jicofo,jvb,jigasi,jibri}
docker-compose -f /opt/jitsi/docker-jitsi-meet/docker-compose.yml up -d

#5 nextcloud UI配置
mkdir -p /opt/nextcloud/volumes/nextcloud && mkdir -p /opt/wordpress/volumes/db
docker-compose -f /opt/nextcloud/nextcloud.yaml up -d 
sed -i "s/.*'dbtype' => 'mysql',.*/'dbtype' => 'mysql',\n'skeletondirectory' => '',/"  /opt/nextcloud/volumes/nextcloud/config/config.php
#sed -i "s/.*0 => '10.0.5.11:8011',.*/0 => '10.0.5.11:8011',\n 1 => 'dvclab.com',/" /opt/nextcloud/volumes/nextcloud/config/config.php
cp /opt/nextcloud/sociallogin  /opt/nextcloud/volumes/nextcloud/apps/
#5.1 Collabora online
docker run -t -p 9980:9980 -e "domain=192.168.1.240" -e "username=admin" -e "password=hanwuji@412"  -e "extra_params=--o:ssl.enable=false" -v /etc/localtime:/etc/localtime:ro --privileged=true --name collabora-online --restart always collabora/code

#6 grafana
docker-compose -f /opt/grafana/grafana.yaml up -d


#root_url = http://10.0.5.11:2000

#7. keycloak
docker network create keycloak-network 
mkdir -p /opt/keycloak/mysql/data
docker-compose -f /opt/keycloak/keycloak.yaml up -d
docker exec -it keycloak /bin/bash
cd  /opt/jboss/keycloak \
&& ./bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master  --user admin  --password hanwuji@412 \
&& ./bin/kcadm.sh update realms/master -s sslRequired=NONE

#8 wireguard
apt-get install wireguard resolvconf
echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" > /etc/sysctl.d/wg.conf
sysctl --system
touch /etc/systemd/system/wgui.service /etc/systemd/system/wgui.path \
&& cat > /etc/systemd/system/wgui.service <<EOF
[Unit]
Description=Restart WireGuard
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart wg-quick@wg0.service
EOF
cat > /etc/systemd/system/wgui.path <<EOF
[Unit]
Description=Watch /etc/wireguard/wg0.conf for changes

[Path]
PathModified=/etc/wireguard/wg0.conf

[Install]
WantedBy=multi-user.target  
EOF
systemctl enable wgui.{path,service} \
&& systemctl start wgui.{path,service}
mkdir -p /opt/wgui/db
docker-compose -f /opt/wgui/docker-compose.yml up -d
cat > /opt/wgui/db/server/users.json <<EOF
{
    "username": "${name}",
    "password": "${pwd}"
}
EOF
docker restart wgui
# UI界面配置

