FROM ruby:2.7.2
RUN apt-get update -y
RUN apt-get install libsodium-dev -y
ADD Gemfile /Gemfile
RUN bundle install
ADD *.rb ./
ADD test ./test
RUN chmod +x /entrypoint.rb
RUN git config --global credential.helper store
RUN cd test && ruby parseconfig.rb
ENTRYPOINT ["/entrypoint.rb"]
