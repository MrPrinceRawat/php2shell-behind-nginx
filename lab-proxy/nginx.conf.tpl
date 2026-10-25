worker_processes 1;
pid /run/nginx.pid;
events { worker_connections 2048; }
http {
    access_log off;
    client_max_body_size 0;
    client_body_buffer_size 16k;
    server {
        listen 80;
        location / {
            proxy_pass http://127.0.0.1:8080;
            proxy_http_version 1.1;
            proxy_request_buffering @BUFFERING@;
            proxy_set_header Host $host;
            proxy_set_header Connection "";
            proxy_read_timeout 180s;
            proxy_send_timeout 180s;
        }
    }
}
