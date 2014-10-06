proc channel_input {fh i} {
    gets $fh line
    if {[eof $fh]} {
        fileevent $fh readable {}
        catch {close $fh}

        lassign $::channel_map($fh) url active

        switch $active {
            "0" {
                incr ::total_downloads -1
            }
            "1" {
                incr ::active_downloads -1
            }
            default {
                puts "Error opening [lindex $::channel_map($fh) 0]"
                incr ::total_downloads -1
            }
        }

        return
    }

    if {[regexp "ERROR" $line]} {
        puts "$i -> $line"
        return
    }

    if {[regexp {Destination: (.*?)$} $line -> A]} {
        puts "Download: $A"
        lassign ::channel_map($fh) url
        set ::channel_map($fh) [list $url 1]

        incr ::active_downloads
        lappend ::target_list $A
    }

    if {[regexp {(.*?) has already been downloaded$} $line -> A]} {
        puts "Already downloaded: $A"
        lassign ::channel_map($fh) url
        set ::channel_map($fh) [list $url 0]
    }

    set exp {^.*? (.*?%).*? of (.*?)MiB at (.*?)([M|K])iB/s ETA.*?$} 
    if {[regexp $exp $line -> A B C D]} {
        set ::percentage_map($i) \
                        "[string trim $A] \
                         [string trim $B] \
                         [string trim $C] \
                         [string trim $D]"
    }
}

proc output {} {
    if {$::total_downloads == 0} {
        incr ::finished
        return
    }

    if {[llength [array names ::percentage_map]] != $::total_downloads} {
        after 1000 output
        return
    }

    switch $::toggle {
        "1" {set dot ". "}
        "2" {set dot ".."}
        "3" {set dot ".:"}
        "4" {set dot "::"}
        "5" {set dot "  "}
    }

    incr ::toggle
    
    if {$::toggle > 5} {set ::toggle 1}

    set total_size 0
    foreach {k v} [array get ::percentage_map] {
        lassign $v percentage size speed units
        set total_size [expr {$total_size + $size}]
    }

    set cur_size 0
    set percent 0
    foreach {k v} [array get ::percentage_map] {
        lassign $v percentage size speed units
        regexp {^(\d.*?)\.\d*?%$} $percentage -> A
        #set x [expr {$size * ($A/100.0)}]
        set cur_size [expr {$cur_size + ($size * ($A/100.0))}]
    }

    set percentage [expr {$cur_size / $total_size}]
    set num_p      [expr {int(40 * $percentage)}]
    set num_d      [expr {40 - $num_p}]

    puts -nonewline "\r"
    puts -nonewline "$dot | "
    puts -nonewline "$::active_downloads remaining: "
    puts -nonewline "\[[string repeat # $num_p]"
    puts -nonewline "[string repeat - $num_d]\] "
    puts -nonewline "[expr {int($percentage * 100)}]% "
    puts -nonewline "[expr int($cur_size)]M / [expr int($total_size)]M"
    flush stdout

    if {$::active_downloads == 0} {
        incr ::finished
        return
    }

    after 1000 output
}

set toggle 1
set target_list {}
set finished 0
set active_downloads 0
set total_downloads 0
array set percentage_map {}
array set channel_map {}

set fh [open download_list r]
set data [split [read $fh] \n]

foreach url $data {
    if {$url == {}} {continue}

    set channel [open "|./youtube-dl -c -f 43 -t $url" r+]

    set channel_map($channel) [list $url A]

    fileevent $channel readable "channel_input $channel $total_downloads"
    fconfigure $channel -blocking false -buffering line

    incr total_downloads
}

output

vwait finished

puts ""

foreach target $target_list {
    file rename $target ./archive

    #regsub {\.flv} $target {.mp3} dest
    regsub {\.webm} $target {.mp3} dest

    puts "Convert:  $target"
    exec -ignorestderr avconv -ab 256k -y -i ./archive/$target ./mp3/$dest >& /dev/null
}
