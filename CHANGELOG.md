## 0.1.1

* Fix bug in `OneAndDone.Plug` where `x-request-id` was being overwritten.
* When ignoring headers, provide the original header value in the `original-` prefixed header (e.g. `original-x-request-id`)

## 0.1.0

* Initial release
