FROM ruby:2.7.7
RUN apt-get update -y
RUN apt-get install libsodium-dev -y
ADD Gemfile /Gemfile
RUN bundle install
ADD *.rb ./
ADD test ./test
RUN cd test && ruby parseconfig.rb
RUN rm -rf test
RUN chmod +x /entrypoint.rb
RUN git config --global credential.helper store
ENTRYPOINT ["/entrypoint.rb"]
