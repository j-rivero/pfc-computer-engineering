FROM jenkins
USER root
RUN apt-get update && apt-get install -y sudo
RUN echo "jenkins ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER jenkins
