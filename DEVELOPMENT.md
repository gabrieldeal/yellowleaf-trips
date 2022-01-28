# Install

```
sudo apt update \
  && sudo apt -y install ffmpeg x264 x265 gpsbabel imagemagick libexpat1-dev perl-doc \
  && cd perl \
  && perl Makefile.PL \
  && sudo cpan .
```

# Build

```
TZ='America/Los_Angeles' ./bin/make-trip --title "Northrup Point" --type hike --trip-files-subdir 2021-10-13-northrup-point

./bin/make-location --name "Tiffany"

./bin/build -v -a copy-files --file ../yellowleaf-trips-data/trips/2021-10-12-northrup-cyn

./bin/build -v -skip copy-files
```

# Debugger:

1. Add `$DB::single=1` to code
2. `PERL5OPT="-d" bin/build`

# Line coverage:

`rm -rf cover_db && PERL5OPT=-MDevel::Cover bin/build && cover && ls -l cover_db`
