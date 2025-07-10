# [tinygrad](https://github.com/tinygrad/tinygrad) host for iOS
## [download from the appstore](https://apps.apple.com/app/tinygrad-remote-host/id6746286914)

Run tinygrad code using your iPhone or iPad's GPU

## steps
1. install and open this app on your iPhone or iPad
2. install [tinygrad](https://github.com/tinygrad/tinygrad) on a computer connected to the same wifi network

3. run any tinygrad code
```sh
REMOTE=1 HOST={your iphone/ipad IP address}:6667 python3 examples/gpt2.py --model_size=gpt2
```

Also try [YOLOv8 on tinygrad](https://github.com/roryclear/yolov8-tinygrad-ios), by caching tinygrad remote batches, models can be easily ran locally.

## notes
- tinygrad's REMOTE API is not stable, there is no guarantee that this will work on the newest commit on tinygrad master. You may have to checkout an older tinygrad commit (from the date of the latest commit in this repo). PRs welcome.
- Max allowed app RAM < total RAM. An iPhone 13 (4GB RAM) cannot use over 2GB in a single app for example, it will crash. Each device has its own limit.
- Metal cannot be ran in the background on iOS, the app must be open to run.
- Modifying one line in tinygrad to send batches on copyin() can increase the amount of memory that can be used, depending on the situation. This needs to be fixed within this app.
