FROM ruby:3.1-slim

WORKDIR /app

COPY Gemfile ./
RUN bundle install

COPY generator.rb ./

CMD ["ruby", "generator.rb"]
