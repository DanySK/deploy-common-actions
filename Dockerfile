FROM ruby:2.7.2
RUN apt-get update -y
RUN apt-get install libsodium-dev -y
ADD Gemfile /Gemfile
RUN bundle install
ADD entrypoint.rb /entrypoint.rb
RUN chmod +x /entrypoint.rb
ENTRYPOINT ["/entrypoint.rb"]
