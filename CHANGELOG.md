# Changelog

## 0.1.6

* Fix an issue where the Plug conn wouldn't be halted when responding with an error related to the idempotency key being too long.

## 0.1.5

* Adds a new `build_ttl_fn` option to `OneAndDone.Plug`. Provide a function here to generate a dynamic idempotency TTL per request. If not provided, or if the function returns a non-integer value, OneAndDone falls back to the `ttl` option and then finally the 24 hour default.

## 0.1.4

* Fixes a typo in a Github URL link.

## 0.1.3

* Set content-type response header to application/json when returning a 400 when reusing an idempotency key incorrectly

## 0.1.2

* Limit the max idempotency key length to 255 characters with the option `max_key_length` (disable by setting it to 0)
* Compare the originally stored request with the current request to ensure the request structure matches
    * This is to prevent reusing the idempotency key e.g. on a different route or with different parameters
    * Matching function is configurable with the option `check_requests_match_fn`
* Add option `request_matching_checks_enabled` to skip checking if requests match
* Ensure idempotency keys are unique across the same calls using the same method
    * Calls using the same key but different methods or paths will not be considered duplicates
* Do not cache responses for status codes >= 400 and < 500
    * This is to prevent caching errors that may be retryable
    * 5xx errors are considered non-retryable to reduce system pressure in a failure mode

## 0.1.1

* Support retaining some response headers (e.g. `x-request-id`) and passing along the original header with the prefix `original-` (e.g. `original-x-request-id`)

## 0.1.0

* Initial release
