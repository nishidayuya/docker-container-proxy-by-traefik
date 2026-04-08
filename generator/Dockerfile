FROM ruby:4.0.2-alpine3.23

WORKDIR /app

COPY Gemfile ./
RUN bundle install

COPY generator.rb ./

CMD ["ruby", "generator.rb"]
