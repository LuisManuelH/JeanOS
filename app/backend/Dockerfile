FROM node:22-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install --omit=dev

COPY . .

RUN test -f scripts/preload-redis.js

EXPOSE 3000

CMD ["npm", "start"]
