FROM quay.io/centos/centos:stream8

RUN yum -y upgrade && \
	yum -y install epel-release python3 expect && \
	yum -y localinstall https://github.com/ubccr/xdmod/releases/download/v10.0.0/xdmod-10.0.0-1.0.beta1.el8.noarch.rpm && \
	yum clean all

ENV XDMOD_DB_PORT=3306 \
	XDMOD_DB_USER=xdmod

# Crudini is a tool for manipulating .ini files. We use it in the entrypoint
# script to configure xdmod from information provided via environment
# variables.
RUN pip3 install crudini

# Here we preserve /etc/xmod on the theory that we'll be mounting
# a volume onto /etc/xdmod at runtime. If it's empty, we'll populate
# it using the backup in /etc/xdmod.orig.
RUN cp -a /etc/xdmod /etc/xdmod.orig

# The entrypoint script takes care of configuring xdmod before
# starting up Apache.
COPY xdmod/entrypoint.sh /docker/entrypoint.sh
ENTRYPOINT ["sh", "/docker/entrypoint.sh"]

# An expect script that runs xdmod-setup to create databases and tables.
COPY xdmod/xdmod-setup-init-databases.expect /docker/xdmod-setup-init-databases.expect

# An expect script that runs xdmod-setup to create an admin user
COPY xdmod/xdmod-setup-create-admin-user.expect /docker/xdmod-setup-create-admin-user.expect

COPY httpd/xdmod.conf /etc/httpd/conf.d/xdmod.conf

# We assume that SSL termination will be provided by a proxy
# (like nginx or an openshift route)
RUN rm -f /etc/httpd/conf.d/ssl.conf

# During development we don't want xdmod trying to send email. This script
# simply writes messages into the /messages directory.
COPY fake-sendmail.sh /usr/bin/sendmail
