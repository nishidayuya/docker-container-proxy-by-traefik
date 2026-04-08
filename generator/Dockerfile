FROM ruby:3.1-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile ./
RUN bundle install

COPY generator.rb ./

CMD ["ruby", "generator.rb"]
