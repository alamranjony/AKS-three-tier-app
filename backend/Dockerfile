# backend/Dockerfile
FROM node:22-alpine
WORKDIR /app

# copy package manifests for caching
COPY package.json package-lock.json* ./

# install curl and production dependencies
RUN apk add --no-cache curl \
 && npm ci --omit=dev

# copy app files
COPY . .

EXPOSE 8080
CMD ["node", "index.js"]

