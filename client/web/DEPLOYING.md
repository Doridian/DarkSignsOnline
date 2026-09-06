# Deploying the browser client

The client needs the page to be **cross-origin isolated**. Without it there
is no `SharedArrayBuffer`, without that there is no `Atomics.wait`, and
without that the worker cannot block while a script waits for input. The
page reports this rather than failing quietly, but it will not be usable.

## The two headers

```nginx
add_header Cross-Origin-Opener-Policy   "same-origin"   always;
add_header Cross-Origin-Embedder-Policy "require-corp"  always;
```

Check it worked by opening the console on the page and evaluating
`crossOriginIsolated`. It must be `true`.

### The nginx trap

`add_header` does not merge. **A `location` block containing any
`add_header` discards every one inherited from its parent.** So this looks
right and is not:

```nginx
server {
    add_header Cross-Origin-Opener-Policy   "same-origin"  always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    location ~ \.php$ {
        add_header X-Whatever "value";   # the two above are now gone here
        fastcgi_pass unix:/run/php-fpm/www.sock;
    }
}
```

Repeat both headers in every location that sets any header of its own. An
`include` file with the pair in it keeps that honest.

## Serve the client from the same origin as the API

This is the recommendation, and it makes most of the rest of this document
unnecessary:

```nginx
server {
    server_name darksignsonline.com;

    # The API, unchanged.
    location /api/ {
        include fastcgi_params;
        fastcgi_param HTTP_AUTHORIZATION $http_authorization;
        fastcgi_pass unix:/run/php-fpm/www.sock;
    }

    # The client.
    location /client/ {
        alias /srv/dso/web/www/;
        add_header Cross-Origin-Opener-Policy   "same-origin"  always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        types { application/wasm wasm; }
    }
}
```

Same-origin means no CORS and no COEP question for API calls at all.

## If the client is on a different origin

Two things in the current API configuration will break it.

### `Authorization` is not covered by the wildcard

The API answers a preflight with:

```
access-control-allow-headers: *
```

The wildcard deliberately **does not** cover `Authorization` — the Fetch
standard excludes it, and every current browser enforces that. The client
sends `Authorization` on every call, so the preflight fails and no request
is made. It has to be named:

```nginx
add_header Access-Control-Allow-Headers
    "Authorization, Content-Type, DSO-Protocol-Version" always;
```

`DSO-Protocol-Version` also needs naming: it is a custom header, so it is
not safelisted either, and it is what keeps the server out of its legacy
response mode.

Note that a custom header means **every** cross-origin API call is
preflighted. Same-origin avoids that round trip entirely.

### `*` with credentials is not a valid pair

The API currently sends both:

```
access-control-allow-origin: *
access-control-allow-credentials: true
```

A browser rejects that combination outright for any credentialed request.
It does not bite today, because the client sets `Authorization` as an
ordinary header rather than using `withCredentials` — so the request is not
credentialed in the CORS sense. It will bite the moment anything uses
cookies. Either drop `Access-Control-Allow-Credentials`, or echo the
specific origin instead of `*`.

### Add a resource policy

Cross-origin responses fetched with CORS satisfy COEP on their own, so the
API works once the header above is fixed. Sending this as well costs
nothing and covers anything later fetched without CORS:

```nginx
add_header Cross-Origin-Resource-Policy "cross-origin" always;
```

## Other things COEP breaks

`require-corp` means every cross-origin subresource must opt in. In
practice:

- **Fonts from a CDN stop loading.** Self-host them. The client names
  `Verdana`, `Impact`, `Courier New` and others that scripts select through
  markup; ship the ones that matter and let the rest fall back.
- **Images from another origin stop loading** unless they send
  `Cross-Origin-Resource-Policy`.
- **Analytics and embeds** in `<iframe>` need `credentialless` or their own
  COEP.

`Cross-Origin-Embedder-Policy: credentialless` is the looser alternative: it
drops credentials from no-cors requests instead of demanding CORP. It suits
a page pulling in third-party images, and it does not affect the API calls,
which are CORS requests carrying an explicit header. `require-corp` has
wider support, so prefer it unless something forces otherwise.

## php-fpm

nginx does not pass `Authorization` to FastCGI unless told to, and without
it the API sees every request as anonymous:

```nginx
fastcgi_param HTTP_AUTHORIZATION $http_authorization;
```

## Serving the files

`build.sh` writes everything into `web/www/`. It needs no build step at
serve time — it is static files. Two details:

- `.wasm` must be served as `application/wasm`, or instantiation is slower
  and some setups refuse it.
- `pkg/` and `scripts/` are build output and are not in git.
