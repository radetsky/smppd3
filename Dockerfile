# start from base
FROM ubuntu:16.04
MAINTAINER Alex Radetsky <rad@pearlpbx.com>

# install system-wide deps for python and node
RUN apt-get -yqq update
RUN apt-get -yqq install apt-utils mariadb-server mariadb-client make git libanyevent-perl libreadonly-perl liblog-log4perl-perl libproc-daemon-perl libproc-pid-file-perl libconfig-general-perl libjson-perl libnetsds-perl libmath-random-mt-perl libobject-insideout-perl liblog-dispatch-perl gcc 
RUN cpan -f Data::UUID::MT
 
# copy our application code
RUN mkdir -p /opt/smppd3/AnyEvent
ADD AnyEvent/PacketReader.pm /opt/smppd3/AnyEvent
ADD createdb.sql /opt/smppd3
ADD scheme.sql /opt/smppd3 
ADD Makefile /opt/smppd3 
ADD smppd3.conf /opt/smppd3 
ADD smppd3.pl /opt/smppd3 
ADD setup_db_in_docker.sh /opt/smppd3
ADD docker_smppd.sh /opt/smppd3
RUN chmod +x /opt/smppd3/docker_smppd.sh 
WORKDIR /opt/smppd3

# fetch app specific deps
RUN cd /opt/smppd3 && make 

# Setup database
RUN chmod +x /opt/smppd3/setup_db_in_docker.sh
RUN /opt/smppd3/setup_db_in_docker.sh 
RUN apt-get -yqq clean 
# expose port
EXPOSE 2775

# start app

#CMD [ "python", "./app.py" ]
CMD /opt/smppd3/docker_smppd.sh

