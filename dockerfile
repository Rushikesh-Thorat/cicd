# client/Dockerfile
# Multi-stage build: build with Node, serve static with nginx
FROM node:18-alpine AS build
WORKDIR /app

# copy package files first for caching
COPY package*.json ./
RUN npm ci

# copy sources
COPY . .

# build (CRA -> build/)
RUN npm run build

# Serve with nginx
FROM nginx:stable-alpine AS production
RUN rm -rf /usr/share/nginx/html/*
COPY --from=build /app/build /usr/share/nginx/html

# Add nginx config for SPA routing (optional, recommended)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
