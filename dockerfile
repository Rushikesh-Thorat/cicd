# ---------- Stage 1: build the React app ----------
FROM node:18-alpine AS build
WORKDIR /app

# copy package files first for better cache
COPY package*.json ./
# if you use yarn or pnpm, replace with appropriate commands
RUN npm ci

# copy source
COPY . .

# build (Create React App outputs to build/)
RUN npm run build

# ---------- Stage 2: serve with nginx ----------
FROM nginx:stable-alpine
# remove default static files
RUN rm -rf /usr/share/nginx/html/*

# copy built files from previous stage
COPY --from=build /app/build /usr/share/nginx/html

# optional: copy a custom nginx.conf if you need rewrites for SPA routing
# COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# keep nginx foreground
CMD ["nginx", "-g", "daemon off;"]
