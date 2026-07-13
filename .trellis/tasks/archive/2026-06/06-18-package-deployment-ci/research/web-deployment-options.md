# Web Deployment Options

## Sources

* Flutter web deployment docs: https://docs.flutter.dev/deployment/web
* MDN COOP header docs: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Opener-Policy
* MDN COEP header docs: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Embedder-Policy
* Cloudflare Pages custom headers docs: https://developers.cloudflare.com/pages/configuration/headers/
* Docker multi-stage build docs: https://docs.docker.com/build/building/multi-stage/
* Nginx headers module docs: https://nginx.org/en/docs/http/ngx_http_headers_module.html

## Findings

Flutter's official web deployment path is to run `flutter build web`, which writes a release bundle to `build/web`. The resulting files can be uploaded to a hosting service. In this project, `./tools/rebuild-web` must run before `flutter build web` because the Flutter build step does not regenerate FRB web wasm/js artifacts.

The FRB web path depends on cross-origin isolation. MDN documents that features such as `SharedArrayBuffer` require:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Therefore, the deployment target must support custom response headers. Nginx can add arbitrary response headers with `add_header`, and Cloudflare Pages supports a `_headers` file for static assets.

Docker is useful here mainly as a packaging and serving boundary:

* Build stage can run Flutter/Rust/FRB tooling and produce `build/web`.
* Runtime stage can be a small static server image such as nginx.
* Nginx config can pin COOP/COEP and wasm/static asset behavior in version-controlled config.
* The shipped image contains the exact generated web artifact set, avoiding dependency on host-local `web/pkg`.

Docker is not inherently required for Flutter Web. Static hosting is equally valid if it can run the CI build command sequence and serve the required headers. For this project, Docker is preferable when deploying to a VPS, NAS, home server, Kubernetes, or any environment where we want the runtime server config to travel with the app. Cloudflare Pages or similar static hosting is preferable when we want less infrastructure to operate and can express the required headers there.

## Feasible Approaches

### Approach A: Dockerized nginx runtime (recommended for self-hosted MVP)

CI builds a Docker image. The image build runs the web build sequence, copies `build/web` into an nginx runtime image, and includes nginx config for SPA fallback plus COOP/COEP headers.

Pros:

* Strongest control over headers, MIME behavior, and artifact contents.
* Easy to deploy consistently to VPS, NAS, Kubernetes, or Docker Compose.
* The runtime contract is explicit and versioned with the repo.

Cons:

* Requires container registry and server/runtime management.
* More moving parts than pure static hosting.

### Approach B: Static hosting with custom headers

CI runs the web build sequence and deploys `build/web` to a static host that supports custom response headers, such as Cloudflare Pages.

Pros:

* Less server operation.
* Usually simpler CDN/TLS story.

Cons:

* Must confirm the platform supports the exact COOP/COEP headers and wasm serving behavior.
* Header config can become platform-specific.

### Approach C: GitHub Actions artifact only

CI runs tests/builds and uploads `build/web` as a workflow artifact or GitHub Release asset. Deployment remains manual.

Pros:

* Good first step before committing to hosting.
* Minimal deployment risk.

Cons:

* Does not solve production serving headers by itself.
* Manual deployment can drift from CI.
