# Timezones and leap seconds

In theory, all timezones and leap seconds are are an offset when formatting. So
if I make a way to specify a list of offsets then I have both timezones and leap
seconds implemented. From there I would need some formatting functions to efficiently
be able to format different timezones

Probably:

```zig
DateTime.format(bla, bla); // Default format, do some fancy stuff here
DateTime.formatConfig(.{ .timezone = bla, .adjust_for_leap_seconds = true, .other = bla });
```
