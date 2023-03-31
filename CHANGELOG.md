## 0.1.2

* Limit the max idempotency key length to 255 characters with the option `max_key_length`
* Compare the originally stored request with the current request to ensure the request structure matches
    * This is to prevent reusing the idempotency key e.g. on a different route or with different parameters

## 0.1.1

* Support retaining some response headers (e.g. `x-request-id`) and passing along the original header with the prefix `original-` (e.g. `original-x-request-id`)

## 0.1.0

* Initial release
