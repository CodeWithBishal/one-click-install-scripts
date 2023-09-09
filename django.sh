#!/bin/bash

# Check if the script is run as root (or with sudo)
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

#Variables
NAME = "" # Desired directory and file names(preferably project name in lowercase without spaces or special characters)
USERNAME = ""  # Change this to your desired username
PASSWORD = ""  # Change this to your desired password
GIT_CLONE_LINK = "" # GitHub repo (Name should match with $NAME)
DOMAIN = "" # domain name without https and www e.g. google.com
DOT_ENV = ("") #content of your .env file
ADMIN_EMAIL = ""
DATABASE_NAME = ""
DATABASE_USER = ""
DATABASE_USER_PASSWORD = ""
DATABASE_PASSWORD = ""

sudo apt-get update -y
sudo apt-get upgrade -y

echo "Initial Update Successful"

# Create the user
useradd -m "$USERNAME"  # -m creates the user's home directory

# Set the password for the user
echo "$USERNAME:$PASSWORD" | chpasswd

# Add the user to the sudo group
usermod -aG sudo "$USERNAME"

# Display information about the new user
echo "User $USERNAME has been created with password: $PASSWORD"

# Allow OpenSSH (SSH) traffic through the firewall
ufw allow OpenSSH

# Enable the firewall
ufw enable

apt install -y apache2
echo "Apache2 has been successfully installed."

ufw allow in "Apache Full"

apt-get update -y
apt install -y mysql-server
apt install -y php libapache2-mod-php php-mysql
apt install mysql-server
apt-get install -y python3-pip apache2 libapache2-mod-wsgi-py3
apt-get install -y libmysqlclient-dev
echo "PHP Lib have been successfully installed."

#MYSQL SETUP
mysql -e \
"CREATE DATABASE $DATABASE_NAME;"
mysql -e \
"CREATE USER '$DATABASE_USER'@'localhost' IDENTIFIED WITH authentication_plugin BY '$DATABASE_USER_PASSWORD';"
mysql -e \
"GRANT ALL PRIVILEGES ON *.* TO '$DATABASE_USER'@'localhost' WITH GRANT OPTION;"
mysql -Bse \
"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DATABASE_USER_PASSWORD';FLUSH PRIVILEGES;"
mysql -sfu root "-p$DATABASE_USER_PASSWORD" < "django.sql"
#MYSQL SETUP
echo "Database Setup Sucessful"

sudo chown -R $USERNAME /var/www
git clone "$GIT_CLONE_LINK" "/var/www/" 
echo "Git Clone Sucessful"
echo "$DOT_ENV" > "/var/www/$NAME/.env"

# Update package information
# Install packages without confirmation
cd "/var/www/$NAME/"
pip3 install virtualenv
# Create the virtual environment
virtualenv env
# Activate the virtual environment
source myenv/bin/activate
pip install -r requirements.txt
./manage.py migrate
./manage.py collectstatic --noinput
DJANGO_SUPERUSER_PASSWORD=$PASSWORD python manage.py createsuperuser --username $USERNAME --email $USERNAME --noinput

systemctl restart apache2

echo "Django Config Done"

#THIS WILL BE THE CONTENT BEFORE CERTBOT IS RUN
PRE_CERT=("
<VirtualHost *:80>
        ServerAdmin $ADMIN_EMAIL
        ServerName $DOMAIN
        ServerAlias www.$DOMAIN
        DocumentRoot /var/www/$NAME
        Alias /static /var/www/$NAME/static
        <Directory /var/www/$NAME/static>
               Require all granted
        </Directory>

        <Directory /var/www/$NAME/$NAME>
               <Files wsgi.py>
                       Require all granted
               </Files>
        </Directory>

        WSGIDaemonProcess $NAME python-home=/var/www/$NAME/env python-path=/var/www/$NAME>
        WSGIProcessGroup $NAME
        WSGIScriptAlias / /var/www/$NAME/$NAME/wsgi.py


        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
RewriteEngine on
RewriteCond %{SERVER_NAME} =$DOMAIN [OR]
RewriteCond %{SERVER_NAME} =www.$DOMAIN
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
")
# Create the Apache Config file with the specified content
echo "$PRE_CERT" > "/etc/apache2/sites-available/$NAME.conf"

a2ensite $NAME.conf
# Reload Apache to apply the changes
systemctl reload apache2
echo "Site $SITE_NAME has been enabled."

echo "Start CertBot"
apt install -y certbot python3-certbot-apache
certbot certonly --non-interactive --agree-tos -m $ADMIN_EMAIL -d $DOMAIN -d www.$DOMAIN 
# Optionally, automatically renew the certificate (add this to a cron job)
certbot renew --dry-run
echo "Certbot installed and configured successfully."
systemctl reload apache2


NEW_PRE_CERT=("
<VirtualHost *:80>
        ServerAdmin $ADMIN_EMAIL
        ServerName $DOMAIN
        ServerAlias www.$DOMAIN
        #DocumentRoot /var/www/$NAME
        #Alias /static /var/www/$NAME/static
        #<Directory /var/www/$NAME/static>
               #Require all granted
        #</Directory>

        #<Directory /var/www/$NAME/$NAME>
               #<Files wsgi.py>
                       #Require all granted
               #</Files>
        #</Directory>

        #WSGIDaemonProcess $NAME python-home=/var/www/$NAME/env python-path=/var/www/$NAME>
        #WSGIProcessGroup $NAME
        #WSGIScriptAlias / /var/www/$NAME/$NAME/wsgi.py


        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined
RewriteEngine on
RewriteCond %{SERVER_NAME} =$DOMAIN [OR]
RewriteCond %{SERVER_NAME} =www.$DOMAIN
RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>
")
# Create the Apache Config file with the specified content
echo "$NEW_PRE_CERT" > "/etc/apache2/sites-available/$NAME.conf"

POST_CERT = ("
<IfModule mod_ssl.c>
<VirtualHost *:443>
        ServerAdmin $ADMIN_EMAIL
        ServerName $DOMAIN
        ServerAlias www.$DOMAIN
        DocumentRoot /var/www/$NAME
        Alias /static /var/www/$NAME/static
        <Directory /var/www/$NAME/static>
               Require all granted
        </Directory>

        <Directory /var/www/$NAME/$NAME>
               <Files wsgi.py>
                       Require all granted
               </Files>
        </Directory>

        WSGIDaemonProcess $NAME python-home=/var/www/$NAME/env python-path=/var/www/$NAME>
        WSGIProcessGroup $NAME
        WSGIScriptAlias / /var/www/$NAME/$NAME/wsgi.py
        ErrorLog ${APACHE_LOG_DIR}/error.log
        CustomLog ${APACHE_LOG_DIR}/access.log combined

Include /etc/letsencrypt/options-ssl-apache.conf
SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
</VirtualHost>
</IfModule>
")
echo "$POST_CERT" > "/etc/apache2/sites-available/$NAME-le-ssl.conf"
systemctl reload apache2
echo "Website is Now Accessible"
sudo apt-get autoremove -y
sudo apt-get clean