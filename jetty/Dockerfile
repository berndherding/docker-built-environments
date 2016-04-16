FROM jetty:latest

COPY ROOT/ /var/lib/jetty/webapps/ROOT

# RUN ls -la /var/lib/jetty/webapps

# prevayler wants to create a user's directory
RUN mkdir /Users

# all jetty instances need to write to the /Users dir
RUN chmod 777 /Users
