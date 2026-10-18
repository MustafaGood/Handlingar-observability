# Proposal: Rails and Sidekiq metrics in the application image

## Problem

`alaveteli-web` and `alaveteli-sidekiq` do not expose `/metrics`. The first
version uses Traefik and a blackbox probe instead. That shows whether the
site answers, and the error rate at the proxy. It does not show Sidekiq queue
depth, failed jobs, or Puma threads.

## Change

Add the `yabeda-rails` and `yabeda-sidekiq` gems to the application image and
serve `/metrics` on port 3000. This is an image change owned by the
application, not by the observability namespace.

## If this is not applied

The Alaveteli dashboard still shows request rate, 5xx, and latency from
Traefik. The Sidekiq panels stay on pod readiness and log lines. Queue depth
stays empty.
