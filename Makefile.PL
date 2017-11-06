use ExtUtils::MakeMaker 6.64;

WriteMakefile(
    'NAME' => 'Scramble',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 6.64,
    },
    BUILD_REQUIRES => {
        'Template' => 0,
    },
    PREREQ_PM => {
        'Exporter' => 0,
        'strict' => 0,
        'warnings' => 0,
        'vars' => 0,
        'Date::Manip' => 0,
        'DateTime' => 0,
        'Filesys::CygwinPaths' => 0,
        'Geo::Coordinates::UTM' => 0,
        'Getopt::Long' => 0,
        'HTML::Entities' => 0,
        'Image::ExifTool' => 0,
        'JSON' => 0,
        'List::Util' => 0,
        'MIME::Types' => 0,
        'Spell' => 0,
        'Spreadsheet::Read' => 0,
        'URI::Encode' => 0,
        'XML::Generator' => 0,
        'XML::RSS' => 0,
        'XML::Simple' => 0,
    },
    TEST_REQUIRES => {
    },
);
