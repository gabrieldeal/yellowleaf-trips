# Install

```
sudo add-apt-repository ppa:jonathonf/ffmpeg-3 && sudo apt update && sudo apt install ffmpeg libav-tools x264 x265
sudo apt-get install gpsbabel imagemagick libexpat1-dev perl-doc
cd perl && perl Makefile.PL && sudo cpan .
```

# Debugger:

1. Add `$DB::single=1` to code
2. `PERL5OPT="-d" bin/build`

# Line coverage:

`rm -rf cover_db && PERL5OPT=-MDevel::Cover bin/build && cover && ls -l cover_db`
