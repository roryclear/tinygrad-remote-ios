# [tinygrad](https://github.com/tinygrad/tinygrad) host for iOS
## [download from the appstore](https://apps.apple.com/app/tinygrad-remote-host/id6746286914)

Run tinygrad code using your iPhone or iPad's GPU

## steps
1. install and open this app on your iPhone or iPad
2. install this [tinygrad fork](https://github.com/roryclear/tinygrad) (new_ios branch) on a computer connected to the same wifi network
```
git clone -b new_ios https://github.com/roryclear/tinygrad.git
cd tinygrad
pip install -e .
```
3. run any tinygrad code
```sh
DEV=IOS IP={your iphone/ipad IP address}:6667 PYTHONPATH=. python3.11 examples/gpt2.py --model_size=gpt2
```

Also try [YOLOv8 on tinygrad](https://github.com/roryclear/yolov8-tinygrad-ios), by caching tinygrad remote batches, models can be easily ran locally.

## notes
- Max allowed app RAM < total RAM of iOS device.
- Metal cannot be ran in the background on iOS, the app must be open to run.
