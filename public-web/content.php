<?php
declare(strict_types=1);

return [
    'version' => '0.1',
    'navigation' => [
        ['section' => 'screenshots', 'label' => 'Screenshots'],
        ['section' => 'workflow', 'label' => 'Workflow'],
        ['section' => 'build', 'label' => 'Build from source'],
        ['section' => 'support', 'label' => 'Support'],
        ['section' => 'get', 'label' => 'Get ZIFburn', 'button' => true],
    ],
    'screenshots' => [
        [
            'file' => 'chip-search.jpg',
            'alt' => 'ZIFburn filtering the TL866A/CS device database with the multi-word search 27C512 DIP',
            'width' => 2852, 'height' => 1650, 'portrait' => false,
            'label' => '01 / CHIP SEARCH',
            'title' => 'Your chip, a few keystrokes away.',
            'description' => 'Search by several words, filter by programmer, and return to favorites and recent devices. Open the picker with ⌘L.',
        ],
        [
            'file' => 'hex-buffer.jpg',
            'alt' => 'A 64 KB example image in the ZIFburn hex buffer with CRC32, Sum16 and a 28-pin socket placement diagram',
            'width' => 2852, 'height' => 1650, 'portrait' => false,
            'label' => '02 / IMAGE INSPECTION',
            'title' => 'See the bytes before you burn.',
            'description' => 'Read hex and ASCII side by side. Find byte patterns or text, compare an image, trim unused fill, or pad to the selected chip’s size.',
        ],
        [
            'file' => 'adapter-banks.jpg',
            'alt' => 'The adapter inspector configured for a 27C322 EPROM with eight 512 KB banks, three DIP switches and the 27c322 slide-switch position',
            'width' => 2852, 'height' => 1650, 'portrait' => false,
            'label' => '03 / BANK-SWITCHED ADAPTERS',
            'title' => 'Big EPROMs, one bank at a time.',
            'description' => 'The 27C160/322/400/800 adapter workflow shows the switch positions for each part, with board-polarity and 16-bit byte-order controls.',
        ],
        [
            'file' => 'themes.jpg',
            'alt' => 'ZIFburn Appearance settings with 13 theme previews including Catppuccin, Nord, Dracula, Solarized, Phosphor and Amber',
            'width' => 1360, 'height' => 1200, 'portrait' => true,
            'label' => '04 / APPEARANCE',
            'title' => 'Make the bench feel like yours.',
            'description' => 'Choose native System, Light or Dark, four Catppuccin palettes, Nord, Dracula, Solarized Light and Dark, or the Phosphor and Amber CRT themes.',
        ],
    ],
    'questions' => [
        [
            'question' => 'Which programmers does ZIFburn work with?',
            'answer' => 'ZIFburn is a front-end for minipro, covering TL866A/CS, TL866II+, T48, T56 and T76 workflows. Available devices and hardware functions depend on your installed minipro version and programmer.',
        ],
        [
            'question' => 'Which image formats can I use?',
            'answer' => 'Open binary and Intel HEX images in the buffer. Use Write File or Verify Against File to pass S-record images directly to minipro. To inspect an S-record image in the buffer, convert it to binary or Intel HEX first.',
        ],
        [
            'question' => 'Does Burn always verify?',
            'answer' => 'Burn performs a blank check and then writes the image. Verification is enabled by default. If you enable Skip verify for a chip, the confirmation and result messages reflect that choice.',
        ],
        [
            'question' => 'Do I need to change programming voltages?',
            'answer' => 'Start with the selected chip’s defaults. For supported devices, the inspector exposes VPP, VDD, VCC and pulse controls. Follow the chip datasheet and your adapter’s guide before applying overrides.',
        ],
        [
            'question' => 'Can I inspect files without a programmer?',
            'answer' => 'Yes. Open an image to inspect its hex, ASCII and checksums, find patterns, compare files, or trim and pad the buffer. A connected programmer is needed for hardware operations.',
        ],
    ],
];
