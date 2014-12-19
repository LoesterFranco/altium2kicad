#!/usr/bin/perl -w
use strict;
use Math::Bezier;
use POSIX qw(strftime);

my $searchimagemagick="\\Program Files\\ImageMagick-6.8.9-Q16\\";

my $imagemagick=-d $searchimagemagick?$searchimagemagick:"";

# Things that are missing in KiCad (BZR5054):
# Y2038 support: The "unique" timestamps are only 32 Bit epoch values, any larger numbers are cut off without any error or warning. At the moment those timestamps are only used for uniqueness, but they might be used for more versioning/historisation in the future.
# The unique timestamps only have a 1 second accuracy. If several people are working together on a hierarchical project, they might create 2 different objects in the same second. Fast Generators and Converters or Plugins might also create many objects in the same second.
# Bezier curves for component symbols -> WONTFIX -> Workaround
# Multi-line Text Frames
# A GND symbol with multiple horizontal lines arranged as a triangle
# Individual colors for single objects like lines, ...
# Ellipse -> Workaround: They have to be approximated
# Round Rectangle -> Workaround: They have to be approximated
# Elliptical Arc -> Workaround: They have to be approximated
# Printing does not work correctly
# Exporting to PDF only creates a single page, does not work for hierarchical schematics yet
# Arcs with >=180 degrees angle. Workaround: Such arcs are splitted into 3 parts

# Things that are missing in Altium:
# Altium does not differentiate between "Power-In" and "Power-Out", it only has "Power"
# -> therefore the Input-Ouput connectivity between Power-In and Power-Out cannot be checked by the KiCad Design-Rules-Check
# Possible workaround: Map Altium-Power to KiCad-Power-In or KiCad-Power-Out and disable the checks in KiCad by allowing Power-In <-> Power-In connections
# When necessary work through all Power Pins and correct the In-Out setting afterwards

# Things that are missing in this converter:
# Automatic layer assignment, at the moment this converter is specialized for Novena, it might not work correctly for other projects with different layer definitions
# Worksheet definitions

# Documentation for the Altium Schematic Fileformat can be found at 
# https://github.com/vadmium/python-altium/blob/master/format.md

# Security considerations
# This tool is currently not designed to be executed on malicious data, so do not run a public webservice with it
# The core parsing code should be safe, the biggest risk is likely the invocation of ImageMagick for image conversion


my $pi=3.14159265359;

my $USELOGGING=1;
my $globalcomp="";
my %globalcontains=();
my %rootlibraries=();
my $ICcount=0;
our $timestamp=time();
my %hvmap=("0"=>"H","1"=>"V","2"=>"H","3"=>"V");
our %uniquereferences=();

#Reads a file with one function
sub readfile($)
{
  if(open(RFIN,"<$_[0]"))
  {
    my $old=$/;
    undef $/;
	binmode RFIN;
    my $content=<RFIN>;
    $/=$old;
    close RFIN;
    return($content);
  }
  return "";
}

sub uniqueid2timestamp($)
{
  my $v=$timestamp--;
  return sprintf("%08X",$v);
  # Old code that converts UniqueIDs to Timestamps, unfortunately we don´t have the UniqueIDs where we need Timestamps :-(
  my $ret="";
  my $A=unpack("C","A");
  foreach(split "",$_[0])
  {
    $ret.=sprintf("%01X",(10+unpack("C",$_)-$A)%16);
  }
  return $ret;
}

sub uniquify($)
{
  my $ref=$_[0];
  if(defined($uniquereferences{$ref}))
  {
    for(2 .. 1000)
	{
  	  if(!defined($uniquereferences{$_[0]."_$_"}))
	  {
	    $ref=$_[0]."_$_";
	    last;
	  }
    }
  }
  $uniquereferences{$ref}=1;
  return $ref;
}


foreach my $filename(glob('"*/Root Entry/FileHeader.dat"'))
{
  print "Handling $filename\n";
  my $short=$filename; $short=~s/\/Root Entry\/FileHeader\.dat$//;
  open IN,"<$filename";
  undef $/;
  my $content=<IN>;
  close IN;
  
  next unless defined($content);
  next unless length($content)>4;
  next if(unpack("l",substr($content,0,4))>length($content));

  my $text="";
  my @a=();

  open OUT,">$filename.txt";
  my $line=0;
  while(length($content)>4)
  {
    my $len=unpack("l",substr($content,0,4));
    
    #print "len: $len\n";
    my $data=substr($content,4,$len); 
    if($data=~m/\n/)
    {
      print "Warning: data contains newline!\n";
    }
    $data=~s/\x00//g;
    push @a,"|LINENO=$line|".$data;
    $text.=$data."\n";
    print OUT $data."\n";
    substr($content,0,4+$len)="";  
	$line++;
  }
  close OUT;


  open LOG,">$short.log" if($USELOGGING);
  open LIB,">$short-cache.lib";
  my $timestamp=strftime "%d.%m.%Y %H:%M:%S", localtime;
  print LIB "EESchema-LIBRARY Version 2.3  Date: $timestamp\n#encoding utf-8\n";

  open OUT,">$short.sch";
  print OUT "EESchema Schematic File Version 2\n";
  
  my %formats=(7=>"C 22000 17000",6=>"B 17000 11000",5=>"A 11000 8500");
  #my %formats=(7=>"A3 16535 11693",6=>"A4 11693 8268",5=>"User 8268 5846");
  
  my $sheetstyle=6; $sheetstyle=$1 if($text=~m/SHEETSTYLE=(\d+)/);
  my $sheetformat=$formats{$sheetstyle};
  if($text=~m/WORKSPACEORIENTATION=1/)
  {
    $sheetformat="$1 $3 $2 portrait" if($sheetformat=~m/(\w+) (\d+) (\d+)/);
  }
  
  my $sheety=12000; $sheety=$1 if($sheetformat=~m/\w+ \d+ (\d+)/);

  my $datetext=strftime "%d %m %Y", localtime;

  print OUT <<EOF
LIBS:power
LIBS:device
LIBS:transistors
LIBS:conn
LIBS:linear
LIBS:regul
LIBS:cmos4000
LIBS:adc-dac
LIBS:memory
LIBS:xilinx
LIBS:special
LIBS:microcontrollers
LIBS:dsp
LIBS:microchip
LIBS:analog_switches
LIBS:motorola
LIBS:texas
LIBS:intel
LIBS:audio
LIBS:interface
LIBS:digital-audio
LIBS:philips
LIBS:display
LIBS:cypress
LIBS:siliconi
LIBS:opto
LIBS:atmel
LIBS:contrib
LIBS:valves
EELAYER 27 0
EELAYER END
\$Descr $sheetformat
encoding utf-8
Sheet 1 1
Title "$short"
Date "$datetext"
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
\$EndDescr
EOF
;

  my %parts=();
  my $prevfilename="";
  my $prevname="";
  my $symbol="";
  my %globalf=();
  my $globalp="";
  my %globalcomment=();
  my %globalreference=();
  my %componentheader=();
  my %designatorpos=();
  my %commentpos=();
  my %xypos=();
  my %lib=();
  our %componentdraw=();
  our %componentcontains=();
  our $LIBREFERENCE;
  my %partcomp=();
  my $relx=0;
  my $rely=0;
  my $nextxypos=undef;
  my $CURRENTPARTID=undef;
  my %partorientation;
  my $OWNERPARTDISPLAYMODE=undef;
  my $OWNERLINENO=0;
  
  my %fontsize=();
  my %fontbold=();
  my %fontkursiv=();
  my %fontrotation=();
  
  my %winkel=("0"=>0,"1"=>90,"2"=>180,"3"=>270);

  # Rotates 2 coordinates x y around the angle o and returns the new x and y
  sub rotate($$$) # x,y,o
  {
    my $o=$_[2]; 
	my $m=$_[2]&4;
	$o&=3; # Perhaps mirroring needs something else?
	#orient=("0"=>"1    0    0    -1","1"=>"0    1    1    0","2"=>"-1   0    0    1","3"=>"0    -1   -1   0");
	if(!$o)
	{
	   return($m?-$_[0]:$_[0],$_[1]);
	}
	elsif($o eq "1")
	{
	   return($m?-$_[1]:$_[1],-$_[0]);
	}
	elsif($o eq "2")
	{
	   return($m?$_[0]:-$_[0],-$_[1]);
	}
	elsif($o eq "3")
	{
	   #print "Drehe 3\n";
	   return($m?$_[1]:-$_[1],$_[0]);
	}
  }
  
  foreach my $b(@a)
  {
    #print "b: $b\n";
    my %d=();
    my @l=split('\|',$b);
    foreach my $c(@l)
    {
      #print "c: $c\n";
      if($c=~m/^([^=]*)=(.*)$/)
      {
        #print "$1 -> $2\n";
        $d{$1}=$2;
      }
    }
    # Now we have parsed key value pairs into %d
	
	my $o="";
	my %ignore=("RECORD"=>1,"OWNERPARTID"=>1,"OWNERINDEX"=>1,"INDEXINSHEET"=>1,"COLOR"=>1,"READONLYSTATE"=>1,"ISNOTACCESIBLE"=>1,"LINENO"=>1);
	foreach(sort keys %d)
	{
	  next if defined($ignore{$_});
	  $o.="$_=$d{$_}|";$o=~s/\r\n//s;
	}
	
	print LOG sprintf("RECORD=%2d|LINENO=%4d|OWNERPARTID=%4d|OWNERINDEX=%4d|%s\n",defined($d{'RECORD'})?$d{'RECORD'}:-42,$d{'LINENO'},defined($d{'OWNERPARTID'})?$d{'OWNERPARTID'}+1:-42,defined($d{'OWNERINDEX'})?$d{'OWNERINDEX'}+1:-42,$o) if($USELOGGING);

    next unless defined($d{'RECORD'});
    my $f=11;
 
	
	my $dat="";
	
	sub drawcomponent($)
	{
  	  $componentdraw{$LIBREFERENCE}.=$_[0] unless(defined($componentcontains{$LIBREFERENCE}{$_[0]}));
      $componentcontains{$LIBREFERENCE}{$_[0]}=1;
	}
	
	
	next if(defined($d{'ISHIDDEN'}) && $d{'ISHIDDEN'} eq "T");

	if(defined($OWNERPARTDISPLAYMODE) && defined($d{'OWNERINDEX'}))
	{
	  #print "Checking for\nOWNERINDEX: $d{'OWNERINDEX'} vs. ".($OWNERLINENO-1)." ?\n $OWNERPARTDISPLAYMODE vs. ".($d{'OWNERPARTDISPLAYMODE'}||-1)." ?\n";
	  next if ((($d{'OWNERINDEX'} || 0) eq $OWNERLINENO-1) && ($d{'OWNERPARTDISPLAYMODE'}||-1) ne $OWNERPARTDISPLAYMODE); 
	}
	
    if(defined($d{'OWNERPARTID'}) && $d{'OWNERPARTID'}>=0)
	{
	  if(defined($CURRENTPARTID))
	  {
        next if($CURRENTPARTID ne $d{'OWNERPARTID'});
	  }

	  if($d{'RECORD'} eq '4') # Label
	  {
	    #|RECORD=4|LOCATION.X=40|TEXT=I2C mappings:|OWNERPARTID=-1|INDEXINSHEET=26|COLOR=8388608|LOCATION.Y=500|FONTID=3
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
        my $fid=4+$globalf{$globalp}++;
        my $o=($d{'ORIENTATION'}||0)*900;
		my $size=$fontsize{$d{'FONTID'}}*6;
	    drawcomponent "T $o $x $y $size 0 1 1 \"$d{'TEXT'}\" Normal 0 L B\n";
	  }
	  elsif($d{'RECORD'} eq '32') # Sheet Name
	  {
	    #|RECORD=32|LOCATION.X=40|TEXT=U_02cpu_power|OWNERINDEX=42|OWNERPARTID=-1|COLOR=8388608|INDEXINSHEET=-1|LOCATION.Y=240|FONTID=1
		my $f=$globalf{$globalp}++;
	    $dat.="F $f \"$d{'TEXT'}\" H ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)."\n";		
	  }
	  elsif($d{'RECORD'} eq '13') # Line
	  {
	    #|RECORD=13|ISNOTACCESIBLE=T|LINEWIDTH=1|LOCATION.X=581|CORNER.Y=1103|OWNERPARTID=1|OWNERINDEX=168|CORNER.X=599|COLOR=16711680|LOCATION.Y=1103
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		drawcomponent "P 2 0 1 10 $x $y $cx $cy\n";
	  }
	  elsif($d{'RECORD'} eq '14') # Rectangle
	  {
	    #RECORD=14|OWNERPARTID=   8|OWNERINDEX=  27|AREACOLOR=11599871|CORNER.X=310|CORNER.Y=1370|ISSOLID=T|LINEWIDTH=2|LOCATION.X=140|LOCATION.Y=920|OWNERINDEX=27|TRANSPARENT=T|
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		drawcomponent "S $x $y $cx $cy 0 1 10 f\n";
	  }
 	  elsif($d{'RECORD'} eq '28') # Text Frame
	  {
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
        ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		my $text=$d{'TEXT'}; $text=~s/\~1/\~/g; $text=~s/ /\~/g;
		if($text=~m/\n/)
		{
		  print "Line-breaks not implemented yet!\n";
		}
		drawcomponent "T 0 $x $y 100 0 1 1 $text 1\n";
      }	  
	  elsif($d{'RECORD'} eq '2') # Pin
	  {
	    my $oldname=$d{'NAME'} || "P";
		$oldname=~s/ //g;
		our $state=0;
		my $name="";
		foreach(split("",$oldname))
		{
          if($state==0)
          {
		    if($_ eq "\\")
			{
			  $state=1;
			}
			elsif($_ eq " ")
			{}
			else
			{
			  $name.=$_;
			}
          }
		  elsif($state==1)
		  {
		    if($_ eq "\\")
			{
			  $name.=$_;
			}
			else
			{
			  $name.="~".$_;
			  $state=2;
			}
		  }
		  elsif($state==2)
		  {
		    if($_ eq "\\")
			{
			  $state=3;
			}
			else
			{
			  $name.="~".$_;
			  $state=0;
			}
		  }
		  elsif($state==3)
		  {
		    if($_ eq "\\")
			{
			  $name.="".$_;
			  $state=2;
			}
			else
			{
			  $name.="".$_;
			  $state=2;
			}
		  }
		}
		
		if(defined($d{'LOCATION.X'})&&defined($d{'LOCATION.Y'}))
		{
		  my %dirtext=("0"=>"L","1"=>"D","2"=>"R","3"=>"U");
		  my $pinorient=$d{'PINCONGLOMERATE'}&3;
		  my $pinnamesize=($d{'PINCONGLOMERATE'}&8)?70:1; # There is a bug in KiCad´s plotting code BZR5054, which breaks all components when this size is 0
		  my $pinnumbersize=($d{'PINCONGLOMERATE'}&16)?70:1; # The :1 should be changed to :0 as soon as the bug is resolved.
		  my %map2=("0"=>"0","1"=>"3","2"=>"2","3"=>"1");
		  $pinorient+=$map2{$partorientation{$globalp}&3}; $pinorient&=3;
		  my $mirrored=$partorientation{$globalp}&4;
		  my $dir=$dirtext{$pinorient};
		  my $x=$d{'LOCATION.X'}*$f;
		  my $y=$d{'LOCATION.Y'}*$f;
		  my $pinlength=$d{'PINLENGTH'}*$f;
		  my $electrical="U";
		  
		  $x-=$relx;
		  $y-=$rely;
          ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		  
		  my %mirrors=("R"=>"L","L"=>"R","D"=>"D","U"=>"U");
		  $dir=$mirrors{$dir} if($mirrored);

		  $x-=$pinlength if($dir eq "R");
		  $x+=$pinlength if($dir eq "L");
		  $y+=$pinlength if($dir eq "D");
		  $y-=$pinlength if($dir eq "U");
		  my $E="I"; my %electricmap=("0"=>"I","1"=>"B","2"=>"O","3"=>"C","4"=>"P","5"=>"T","6"=>"E","7"=>"W"); 
		  $E=$electricmap{$d{'ELECTRICAL'}} || "I" if(defined($d{'ELECTRICAL'}));
		  my $F=""; # $F=" F" if($d{'ELECTRICAL'}eq "7"); Unfortunately, Altium and KiCad have different meanings for the same symbols
		  #$pinnumbersize=60; $pinnamesize=60;  # Plotting hangs when the sizes are 0, this should be changed 
		  # $name must not be empty for KiCad!
		  drawcomponent "X $name $d{DESIGNATOR} $x $y $pinlength $dir $pinnumbersize $pinnamesize 0 1 $E$F\n";
	    }
		else
		{
		  print "$d{'RECORD'} $name without Location!\n";
		}
	  
	  }
	
	  elsif($d{'RECORD'} eq '6') # Polyline
	  {
        #RECORD= 6|OWNERPARTID=   1|OWNERINDEX=1468|LINEWIDTH=1|LOCATIONCOUNT=2|OWNERINDEX=1468|X1=440|X2=440|Y1=1210|Y2=1207|
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		my $cmpd="P $d{LOCATIONCOUNT} 0 1 $d{LINEWIDTH}0 ";
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f)-$relx;
		  my $y=($d{'Y'.$i}*$f)-$rely;
		  ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		  $cmpd.="$x $y ";
		}
		drawcomponent "$cmpd $fill\n";
	  }
	  elsif($d{'RECORD'} eq '7') #Polygon
	  {
	    #RECORD= 7|OWNERPARTID=   1|OWNERINDEX=3856|AREACOLOR=16711680|ISSOLID=T|LINEWIDTH=1|LOCATIONCOUNT=3|OWNERINDEX=3856|X1=450|X2=460|X3=470|Y1=980|Y2=970|Y3=980|
        my $lwidth=defined($d{'LINEWIDTH'})?$d{'LINEWIDTH'}*10:10;
		my $cmpd="P ".($d{'LOCATIONCOUNT'}+1)." 0 1 $lwidth ";
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f)-$relx;
		  my $y=($d{'Y'.$i}*$f)-$rely;
		  ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		  $cmpd.="$x $y ";
		}
        my $x=($d{'X1'}*$f)-$relx;
		my $y=($d{'Y1'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		$cmpd.="$x $y $fill\n";
		drawcomponent "$cmpd";
	  }
	  elsif($d{'RECORD'} eq '8') # Ellipse
	  {
	    #RECORD= 8|OWNERPARTID=   1|OWNERINDEX=3899|AREACOLOR=16711680|ISSOLID=T|LINEWIDTH=1|LOCATION.X=376|LOCATION.Y=1109|OWNERINDEX=3899|RADIUS=1|SECONDARYRADIUS=1|print "RECORD7: $filename\n";
        my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		drawcomponent "C $x $y ".($d{'RADIUS'}*$f)." 0 1 $d{LINEWIDTH}0 $fill\n";
	  }
	  elsif($d{'RECORD'} eq '12') # Arc
	  {
	    #RECORD=12|ENDANGLE=180.000|LINEWIDTH=1|LOCATION.X=1065|LOCATION.Y=700|OWNERINDEX=738|RADIUS=5|STARTANGLE=90.000|		
        my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $r=($d{'RADIUS'}*$f);
		my $sa="0"; $sa="$1$2" if(defined($d{'STARTANGLE'}) && $d{'STARTANGLE'}=~m/(\d+)\.(\d)(\d+)/);
		my $ea="0"; $ea="$1$2" if(defined($d{'ENDANGLE'}) && $d{'ENDANGLE'}=~m/(\d+)\.(\d)(\d+)/);
		my @liste=();
		if(($ea-$sa)>=1800)
		{
		  # Altium Angles larger than 180 degrees have to be split up in 2 that are each less than 180 degrees, since KiCad cannot handle them.
		  #print "We have to split $sa->$ea\n";
		  push @liste,[$sa,int($sa+($ea-$sa)/3)];
		  push @liste,[int($sa+($ea-$sa)/3),int($sa+2*($ea-$sa)/3)];
		  push @liste,[int($sa+2*($ea-$sa)/3),$ea];
		}
		else
		{
		  push @liste,[$sa,$ea];
		}
        #print "Liste:\n";
		foreach(@liste)
		{
		  my ($sa,$ea)=@$_;
		  #print "  $sa $ea\n";
		  #print "partorient: $partorientation{$globalp}, winkel: ".$winkel{$partorientation{$globalp}&3}."\n";
		  $sa=3600-$winkel{$partorientation{$globalp}&3}*10+$sa;$sa%=3600; $sa-=3600 if($sa>1800);
		  $ea=3600-$winkel{$partorientation{$globalp}&3}*10+$ea;$ea%=3600; $ea-=3600 if($ea>1800);
		  #print "sa: $sa ea:$ea\n";
		  my $sarad=$sa/1800*$pi;
		  my $earad=$ea/1800*$pi;
		  my $x1=int($x+cos($sarad)*$r);
		  my $x2=int($x+cos($earad)*$r);
		  my $y1=int($y+sin($sarad)*$r);
		  my $y2=int($y+sin($earad)*$r);
		  my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		  drawcomponent "A $x $y $r $sa $ea 1 1 $d{LINEWIDTH}0 $fill $x1 $y1 $x2 $y2\n";
		}
      }
	  elsif($d{'RECORD'} eq '41') # Text
	  {
	    #RECORD=41|OWNERPARTID=   1|OWNERINDEX=1568|LOCATION.X=80|LOCATION.Y=846|NAME=Comment|OWNERINDEX=1568|TEXT=2.1mm x 5.5mm DC jack|
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
		($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $text=$d{'DESCRIPTION'} || $d{'TEXT'}; $text=~s/\~/~~/g; $text=~s/\~1/\~/g; $text=~s/ /\~/g; 
		drawcomponent "T 0 $x $y 50 0 1 1 $text 1\n";
	  }
	  else
	  {
	    print "Unhandled Record type within: $d{RECORD}\n";
	  }
	
      push @{$parts{$globalp}},$dat;
	  $partcomp{$globalp}=$LIBREFERENCE;
      $dat="";	  
	}
    else
	{
	  
	  if($d{'RECORD'} eq '4') # Label
	  {
	    #|RECORD=4|LOCATION.X=40|TEXT=I2C mappings:|OWNERPARTID=-1|INDEXINSHEET=26|COLOR=8388608|LOCATION.Y=500|FONTID=3
		my $size=$fontsize{$d{'FONTID'}}*6;
		my $bold=$fontbold{$d{'FONTID'}}?"12":"0";
		my %myrot=("0"=>"0","90"=>"1","270"=>"2");
		my $rot=$d{'ORIENTATION'} || $myrot{$fontrotation{$d{'FONTID'}}};
		#print "FONTROT: $fontrotation{$d{'FONTID'}}\n" if($text=~m/0xA/);
		my $text=$d{'TEXT'}; $text=~s/\~/~~/g;
	    $dat="Text Label ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." $rot    $size   ~ $bold\n$text\n";
	  }
	  elsif($d{'RECORD'} eq '15') # Sheet Symbol
	  {
	    #|SYMBOLTYPE=Normal|RECORD=15|LOCATION.X=40|ISSOLID=T|YSIZE=30|OWNERPARTID=-1|COLOR=128|INDEXINSHEE=41|AREACOLOR=8454016|XSIZE=90|LOCATION.Y=230|UNIQUEID=OLXGMUHL
		$symbol="\$Sheet\nS ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'XSIZE'}*$f)." ".($d{'YSIZE'}*$f);
	    #$dat="\$Sheet\nS ".($symbolx)." ".($symboly)." ".($symbolsizex)." ".($d{'YSIZE'}*$f)."\nF0 \"$prevname\" 60\nF1 \"$prevfilename\" 60\n\$EndSheet\n";
	  }
	  elsif($d{'RECORD'} eq '32') # Sheet Name
	  {
	    #|RECORD=32|LOCATION.X=40|TEXT=U_02cpu_power|OWNERINDEX=42|OWNERPARTID=-1|COLOR=8388608|INDEXINSHEET=-1|LOCATION.Y=240|FONTID=1
		#These Texts are transferred to the Sheet Symbol, and do not need to be duplicated here:
	    #$dat="Text Label ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." 0    60   ~ 0\n".$d{'TEXT'}."\n";
        $prevname=$d{'TEXT'};
      }
	  elsif($d{'RECORD'} eq '33') # Sheet Symbol
	  {
        $prevfilename=$d{'TEXT'} if($d{'RECORD'} eq '33'); $prevfilename=~s/\.SchDoc/\.sch/;	
	    $dat="$symbol\nF0 \"$prevname\" 60\nF1 \"$prevfilename\" 60\n\$EndSheet\n";
		$rootlibraries{"$short-cache.lib"}=1;
	  }	  
	  elsif($d{'RECORD'} eq '27') # Wire
	  {
	    #|RECORD=27|Y2=190|LINEWIDTH=1|X2=710|LOCATIONCOUNT=2|X1=720|OWNERPARTID=-1|INDEXINSHEET=26|COLOR=8388608|Y1=190
		my $prevx=undef; my $prevy=undef;
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f);
		  my $y=$sheety-($d{'Y'.$i}*$f);
    	  $dat.=#"Text Label $x $y 0 60 ~\n$d{LINENO}\n".
		  "Wire Wire Line\n	$x $y $prevx $prevy\n" if(defined($prevx));
          $prevx=$x;
		  $prevy=$y;
		}
	  }
	  elsif($d{'RECORD'} eq '13') # Line
	  {
	    #|RECORD=13|ISNOTACCESIBLE=T|LINEWIDTH=1|LOCATION.X=581|CORNER.Y=1103|OWNERPARTID=1|OWNERINDEX=168|CORNER.X=599|COLOR=16711680|LOCATION.Y=1103
	    $dat.="Wire Wire Line\n	".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)."\n";
	    $dat.="Wire Wire Line\n	".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'CORNER.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)."\n";
	    $dat.="Wire Wire Line\n	".($d{'LOCATION.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)." ".($d{'CORNER.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)."\n";
	    $dat.="Wire Wire Line\n	".($d{'CORNER.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f)." ".($d{'CORNER.X'}*$f)." ".($sheety-$d{'CORNER.Y'}*$f)."\n";
	  }
	  elsif($d{'RECORD'} eq '17') # Power Object
	  {
	    #RECORD=17|OWNERPARTID=  -1|OWNERINDEX=   0|LOCATION.X=370|LOCATION.Y=1380|ORIENTATION=1|SHOWNETNAME=T|STYLE=2|TEXT=VCC_1.2V_SW1AB|
		my $px=($d{'LOCATION.X'}*$f);
		my $py=($sheety-$d{'LOCATION.Y'}*$f);
		my $py1=$py+140;
		my $py2=$py+110;
		my $text=$d{'TEXT'};
	    my $SHOWNETNAME=$d{'SHOWNETNAME'}?"0000":"00001";
		my $ts=uniqueid2timestamp($d{'UNIQUEID'});
	    my $PWR="L GND #PWR?$ts";
		my $voltage="1.2V";
        my $device="+1.2V";		
		if($d{'TEXT'}=~m/(0\.75V|1\.2V|1\.5V|1\.8V|2\.5V|2\.8V|3\.0V|3\.3VA|3\.3V|5\.0V|\d+\.\d+V)/)
		{
		  $voltage=$1;
		  $voltage=~s/\.0//;
		  $device="+".$voltage;
		   
          $componentheader{$device}="#\n# $device\n#\nDEF $device #PWR 0 0 Y Y 1 F P";
          $designatorpos{$device}="\"#PWR\" 0 140 20 H I L BNN";
          $commentpos{$device}="\"$device\" 0 110 30 H V L BNN";
          $componentdraw{$device}=<<EOF
P 3 0 0 0  0 0  0 70  0 70 N
X $device 1 0 0 0 U 20 20 0 0 W N
C 0 60 20 0 1 0 N
EOF
;
		}
		elsif($d{'TEXT'}=~m/VDD/)
		{
		  $voltage="VDD";
		  $device=$voltage;
		}
		elsif($d{'TEXT'}=~m/GND/)
		{
		  $voltage="GND";
		  $device=$voltage;
		}
		elsif($d{'TEXT'} eq 'VCOREDIG') # This is a workaround for Novena, it could potentially break other schematics
		{
		  $voltage="1.5V";
		  $device="+1.5V";
		}
		else
		{
  		  print "Voltage: $d{TEXT}\n";
		}
		
		if(defined($d{'STYLE'}) && ($d{'STYLE'}eq"1" || $d{'STYLE'}eq"2"))
		{
		  $PWR="L $device #PWR?$ts"; # $ts";
		  $py1=$py;
		  $py2=$py-70;
		}
        $text=uniquify($text);
        print OUT <<EOF
\$Comp
$PWR
U 1 1 $ts
P $px $py
F 0 "$text" H $px $py1 20  $SHOWNETNAME C CNN
F 1 "+$voltage" H $px $py2 30  0000 C CNN
F 2 "" H $px $py 70  0000 C CNN
F 3 "" H $px $py 70  0000 C CNN
	1    $px $py
	1    0    0    -1  
\$EndComp
EOF
;
	  }
	  elsif($d{'RECORD'} eq '29') # Junction
	  {
	    #RECORD=29|OWNERPARTID=  -1|OWNERINDEX=   0|LOCATION.X=130|LOCATION.Y=1230|
		my $px=($d{'LOCATION.X'}*$f);
		my $py=($sheety-$d{'LOCATION.Y'}*$f);
		$dat.="Connection ~ $px $py\n";
	  }
	  elsif($d{'RECORD'} eq '1')  # Schematic Component
	  {
        #RECORD= 1|OWNERPARTID=  -1|OWNERINDEX=   0|AREACOLOR=11599871|
		#COMPONENTDESCRIPTION=4-port multiple-TT hub with USB charging support|CURRENTPARTID=1|DESIGNITEMID=GLI8024-48_4|DISPLAYMODECOUNT=1|LIBRARYPATH=*|
		#LIBREFERENCE=GLI8024-48_4|
		#LOCATION.X=1380|LOCATION.Y=520|PARTCOUNT=2|PARTIDLOCKED=F|SHEETPARTFILENAME=*|SOURCELIBRARYNAME=*|TARGETFILENAME=*|
		$LIBREFERENCE=$d{'LIBREFERENCE'}; $LIBREFERENCE=~s/ /_/g;
		$LIBREFERENCE.="_".$d{'CURRENTPARTID'} if($d{'PARTCOUNT'}>2);
		$CURRENTPARTID=$d{'CURRENTPARTID'} || undef;
		$OWNERPARTDISPLAYMODE=$d{'DISPLAYMODE'};
		$OWNERLINENO=$d{'LINENO'};
		$globalp++;
		$nextxypos=($d{'LOCATION.X'}*$f)." ".($sheety-$d{'LOCATION.Y'}*$f);
		$partorientation{$globalp}=$d{'ORIENTATION'}||0;
		$partorientation{$globalp}+=4 if(defined($d{'ISMIRRORED'}) && $d{'ISMIRRORED'} eq 'T');
        $xypos{$globalp}=$nextxypos ;
		$relx=$d{'LOCATION.X'}*$f;
		$rely=$d{'LOCATION.Y'}*$f;
	  }
	  elsif($d{'RECORD'} eq '5') # Bezier curves, not component related
	  {
        #RECORD= 6|OWNERPARTID=   1|OWNERINDEX=1468|LINEWIDTH=1|LOCATIONCOUNT=2|OWNERINDEX=1468|X1=440|X2=440|Y1=1210|Y2=1207|
		my @bezpoints=();
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f);
		  my $y=$sheety-($d{'Y'.$i}*$f);
		  push @bezpoints,$x;
		  push @bezpoints,$y;
		}
		#print "Control: @bezpoints ".scalar(@bezpoints)."\n";
		my $bez=Math::Bezier->new(@bezpoints);
		my @linepoints=$bez->curve(10);
		#print "Bezier: @linepoints\n";
		while(scalar(@linepoints)>=4)
		{
		  my $x1=int(shift(@linepoints));
		  my $y1=int(shift(@linepoints));
	      $dat.="Wire Notes Line\n	".int($linepoints[0])." ".int($linepoints[1])." $x1 $y1\n";
        }
		
	  }
	  elsif($d{'RECORD'} eq '8') # Ellipse
	  {
        #RECORD=8|LINENO=10947|OWNERPARTID=0|OWNERINDEX=-42|AREACOLOR=16777215|ISSOLID=T|LINEWIDTH=1|LOCATION.X=148|LOCATION.Y=580|RADIUS=3|SECONDARYRADIUS=3|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
        my $radius=int($d{'RADIUS'})*$f;
		my $secondary=int($d{'SECONDARYRADIUS'})*$f; 
		my $fill=(defined($d{'ISSOLID'})&&$d{'ISSOLID'} eq 'T')?"F":"N";
		
		my $parts=40;		
		for(my $i=0;$i<$parts;$i++)
		{
		  my $x1=int($x+sin((2*$pi*$i/$parts))*$radius);
		  my $y1=int($y+cos((2*$pi*$i/$parts))*$secondary);
		  my $x2=int($x+sin((2*$pi*($i+1)/$parts))*$radius);
		  my $y2=int($y+cos((2*$pi*($i+1)/$parts))*$secondary);
    	  $dat.="Wire Notes Line\n	$x1 $y1 $x2 $y2\n";
		}
	    #$dat.="Text Label $x $y 0 60 ~\nELLIPSE\n";        
	  }
	  elsif($d{'RECORD'} eq '11') # Elliptic Arc
	  {
        #RECORD=11|ENDANGLE=87.556|LINEWIDTH=1|LOCATION.X=170|LOCATION.Y=575|RADIUS=8|RADIUS_FRAC=40116|SECONDARYRADIUS=10|SECONDARYRADIUS_FRAC=917|STARTANGLE=271.258|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
        my $radius=int($d{'RADIUS'})*$f;
		my $secondary=int($d{'SECONDARYRADIUS'})*$f; # Primary and Secondary might be mixed up in the calculation
		my $sa=($d{'STARTANGLE'}+90)*$pi/180;
		my $ea=($d{'ENDANGLE'}+90)*$pi/180; $ea+=$pi*2 if($ea<$sa);
		my $ra=$ea-$sa;
		
		my $parts=50;		
		for(my $i=0;$i<$parts;$i++)
		{
		  my $x1=int($x+sin($sa+($ra*$i/$parts))*$radius);
		  my $y1=int($y+cos($sa+($ra*$i/$parts))*$secondary);
		  my $x2=int($x+sin($sa+($ra*($i+1)/$parts))*$radius);
		  my $y2=int($y+cos($sa+($ra*($i+1)/$parts))*$secondary);
    	  $dat.="Wire Notes Line\n	$x1 $y1 $x2 $y2\n";
		}
	    #$dat.="C $x $y $radius 0 0 $d{LINEWIDTH}\n";
    	#$dat.="Text Label $x $y 0 60 ~\nELLIPSE\n"; 
	  }	  
	  elsif($d{'RECORD'} eq "6") # Polyline
	  {
        #RECORD=6|OWNERPARTID=1|OWNERINDEX=1468|LINEWIDTH=1|LOCATIONCOUNT=2|OWNERINDEX=1468|X1=440|X2=440|Y1=1210|Y2=1207|
		my $prevx=undef; my $prevy=undef;
		foreach my $i(1 .. $d{'LOCATIONCOUNT'})
		{
  		  my $x=($d{'X'.$i}*$f);
		  my $y=$sheety-($d{'Y'.$i}*$f);
    	  $dat.="Wire Notes Line\n	$x $y $prevx $prevy\n" if(defined($prevx));
          $prevx=$x;
		  $prevy=$y;
		}
	  }
	  elsif($d{'RECORD'} eq '25') #Net Label
	  {
        #RECORD=25|OWNERPARTID=  -1|OWNERINDEX=   0|LINENO=2658|LOCATION.X=1420|LOCATION.Y=230|TEXT=PMIC_INT_B|
        my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		my $orientation=$d{'ORIENTATION'} || 0;
    	$dat.="Text Label $x $y $orientation 70 ~\n$d{TEXT}\n";
      }
	  elsif($d{'RECORD'} eq '34') #Designator
	  {
        #RECORD=34|OWNERPARTID=  -1|OWNERINDEX=  27|LINENO=146|LOCATION.X=600|LOCATION.Y=820|NAME=Designator|OWNERINDEX=27|TEXT=U200|
        my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
        my $orientation=$d{'ORIENTATION'} || 0;
		$orientation=($orientation+$partorientation{$globalp})%4;
		
		my $desig="IC"; $desig=$1 if($d{'TEXT'}=~m/^([A-Z]*)/);
		my $ref=uniquify($d{'TEXT'});
		push @{$parts{$globalp}},"F 0 \"$ref\" ".$hvmap{$orientation}." $x $y 60  0000 L BNN\n";

	    $x=($d{'LOCATION.X'}*$f)-$relx;
        $y=($d{'LOCATION.Y'}*$f)-$rely;
		$globalreference{$globalp}=$ref;
		$designatorpos{$LIBREFERENCE}="\"$desig\" $x $y 60 H V L BNN"; # $desig 70 H V L BNN
      }
	  elsif($d{'RECORD'} eq '41') #Parameter
	  {
        #RECORD=41|OWNERPARTID=  -1|OWNERINDEX=2659|ISHIDDEN=T|LINENO=2661|LOCATION.X=1400|LOCATION.Y=260|NAME=PinUniqueId|OWNERINDEX=2659|TEXT=DXTGJKVR|
		#my $ts=uniqueid2timestamp($d{'UNIQUEID'});
	    #print "UNIQ: $d{UNIQUEID} -> $ts\n";
        if($d{'NAME'} eq "Comment")
		{
		  my $x=($d{'LOCATION.X'}*$f)-$relx;
          my $y=($d{'LOCATION.Y'}*$f)-$rely;
      	  my $orientation=$d{'ORIENTATION'} || 0;

		  my $t=""; $t=$LIBREFERENCE; # If we put in $d{'TEXT'} instead then KiCad will load it, but it will break when saving or printing/plotting!, since $d{'TEXT'} is slightly different. 
		  $commentpos{$LIBREFERENCE}="\"".$t."\" $x $y 60 ".$hvmap{$orientation}." V L BNN";
		  $globalcomment{$globalp}=$d{'TEXT'};
		  #print $d{'TEXT'}." -> $t -> $commentpos{$LIBREFERENCE}\n" if($d{'NAME'} eq "Rule");
		  
          $x=($d{'LOCATION.X'}*$f);
		  $y=$sheety-($d{'LOCATION.Y'}*$f);
      	  #$dat.="Text Label $x $y $orientation 70 ~\n$d{TEXT}\n";
          push @{$parts{$globalp}},"F 1 \"".($d{'TEXT'}||"")."\" ".$hvmap{$orientation}." $x $y 60  0000 C BNN\n";
          push @{$parts{$globalp}},"F 2 \"\" H $x $y 60  0000 C CNN\n";
          push @{$parts{$globalp}},"F 3 \"\" H $x $y 60  0000 C CNN\n";

		}
		elsif($d{'NAME'} eq "Rule")
        {
		  my $x=($d{'LOCATION.X'}*$f);
		  my $y=$sheety-($d{'LOCATION.Y'}*$f);
		  my $o=$d{'ORIENTATION'} || 0;
    	  $dat.="Text Label $x $y $o 70 ~\n$d{DESCRIPTION}\n";
		}
		elsif(defined($d{'LOCATION.X'}))
		{
          my $x=($d{'LOCATION.X'}*$f);
		  my $y=$sheety-($d{'LOCATION.Y'}*$f);
		  my $o=$d{'ORIENTATION'} || 0;
    	  $dat.="Text Label $x $y $o 70 ~\n$d{TEXT}\n";
		}
		else
		{
		  #print "Error: Parameter without position!\n";
		}
      }
	  elsif($d{'RECORD'} eq '43') #Comment?
	  {
        #RECORD=41|OWNERPARTID=  -1|OWNERINDEX=2659|ISHIDDEN=T|LINENO=2661|LOCATION.X=1400|LOCATION.Y=260|NAME=PinUniqueId|OWNERINDEX=2659|TEXT=DXTGJKVR|
		if(defined($d{'LOCATION.X'}))
		{
          my $x=($d{'LOCATION.X'}*$f);
		  my $y=$sheety-($d{'LOCATION.Y'}*$f);
		  my $o=$d{'ORIENTATION'} || 0;
    	  $dat.="Text Label $x $y $o 70 ~\n$d{NAME}\n";
		}
		else
		{
		  print "Error: Comment without position !\n";
		}
      }
  	  elsif($d{'RECORD'} eq '22') #No ERC
	  {
        #RECORD=22|OWNERPARTID=  -1|OWNERINDEX=   0|ISACTIVE=T|LINENO=1833|LOCATION.X=630|LOCATION.Y=480|SUPPRESSALL=T|SYMBOL=Thin Cross|
        my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
    	$dat.="NoConn ~ $x $y\n";
      }
	  elsif($d{'RECORD'} =~m/^(10|14)$/) # Rectangle
	  {
	    #RECORD=14|OWNERPARTID=   8|OWNERINDEX=  27|AREACOLOR=11599871|CORNER.X=310|CORNER.Y=1370|ISSOLID=T|LINEWIDTH=2|LOCATION.X=140|LOCATION.Y=920|OWNERINDEX=27|TRANSPARENT=T|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		#($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f);
		my $cy=$sheety-($d{'CORNER.Y'}*$f);
		#($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
	    $dat.="Wire Notes Line\n	$x $y $x $cy\n";
	    $dat.="Wire Notes Line\n	$x $y $cx $y\n";
	    $dat.="Wire Notes Line\n	$x $cy $cx $cy\n";
	    $dat.="Wire Notes Line\n	$cx $y $cx $cy\n";

	  }
	  elsif($d{'RECORD'} eq '30') # Image
	  {
	    #RECORD=30|CORNER.X=810|CORNER.X_FRAC=39800|CORNER.Y=59|CORNER.Y_FRAC=99999|FILENAME=C:\largework\electrical\rdtn\cc-logo.tif|KEEPASPECT=T|LINENO=3428|LOCATION.X=790|LOCATION.Y=40|
		my $x=($d{'LOCATION.X'}*$f);
		my $y=$sheety-($d{'LOCATION.Y'}*$f);
		#($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f);
		my $cy=$sheety-($d{'CORNER.Y'}*$f);
		my $mx=int(($x+$cx)/2);
		my $widthx=abs($x-$cx);
		my $my=int(($y+$cy)/2);
		#print "x:$x y:$y cx:$cx cy:$cy mx:$mx my:$my\n";
		#($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		if(0)
		{
	      $dat.="Wire Notes Line\n	$x $y $x $cy\n";
	      $dat.="Wire Notes Line\n	$x $y $cx $y\n";
	      $dat.="Wire Notes Line\n	$x $cy $cx $cy\n";
	      $dat.="Wire Notes Line\n	$cx $y $cx $cy\n";
     	  $dat.="Text Label $x $y 0 70 ~\n$d{FILENAME}\n";
		}
        #print "$d{FILENAME}\n";		
		my $bmp=$d{'FILENAME'};$bmp=~s/^.*\\//;
		#print "$bmp\n";
		if(!-f $bmp)
		{
		  print "ERROR: $bmp not found!\n";
		}
		my $png=$bmp; $png=~s/\.\w+$/.png/;
		#print "$bmp -> $png\n";
		if(! -f $png)
		{
		  system "\"$imagemagick"."convert\" -colorspace RGB \"$bmp\" \"$png\"";
		}
		my $identify="identify";
		my $ident=`"$imagemagick$identify" "$png"`;
	    #print "$ident\n";
		my $imagex=1; my $imagey=1;
		if($ident=~m/PNG (\w+)x(\w+)/)
		{
		  $imagex=$1; $imagey=$2;
		}
		my $scale=$widthx/$imagex/3.3; $scale=~s/\./,/;
		#print "$png $imagex $imagey $widthx $scale\n";
		$dat.="\$Bitmap\nPos $mx $my\nScale $scale\nData\n";
		my $pngdata=readfile($png);
        foreach(0 .. length($pngdata)-1)
		{
		  $dat.=sprintf("%02X ",unpack("C",substr($pngdata,$_,1)));
		  $dat.="\n" if($_%32 ==31);
		}
		$dat.="\nEndData\n\$EndBitmap\n";

	  }
	  elsif($d{'RECORD'} eq '28') # Text Frame
	  {
		my $x=($d{'LOCATION.X'}*$f)-$relx;
		my $y=($d{'LOCATION.Y'}*$f)-$rely;
        ($x,$y)=rotate($x,$y,$partorientation{$globalp});
		my $cx=($d{'CORNER.X'}*$f)-$relx;
		my $cy=($d{'CORNER.Y'}*$f)-$rely;
		($cx,$cy)=rotate($cx,$cy,$partorientation{$globalp});
		my $text=$d{'TEXT'}; $text=~s/\~1/\~/g; $text=~s/ /\~/g;
		drawcomponent "T 0 $x $y 100 0 1 1 $text 1\n";
		#!!! Line-break, Alignment, ...
      }	  
	  elsif($d{'RECORD'} eq '31') #Sheet
	  {
	    # This has been handled already with other code above.
		my $nfonts=$d{'FONTIDCOUNT'};
		foreach(1 ..$nfonts)
		{
		  my $fontname=$d{'FONTNAME'.$_};
		  my $fontsize=$d{'SIZE'.$_}; $fontsize{$_}=$fontsize;
		  my $rotation=$d{'ROTATION'.$_}||"0"; $fontrotation{$_}=$rotation;
		  my $bold=$d{'BOLD'.$_}||""; $fontbold{$_}=$bold;
		  #print "$_:$fontname:$fontsize:$rotation:$bold\n";
		}
	  }
	  elsif($d{'RECORD'} eq '45') # Packaging
	  {
        #RECORD=45|LINENO=2857|OWNERPARTID= -42|OWNERINDEX=2856|DATAFILECOUNT=1|DESCRIPTION=SOT23, 3-Leads, Body 2.9x1.3mm, Pitch 0.95mm, Lead Span 2.5mm, IPC Medium Density|ISCURRENT=T|MODELDATAFILEENTITY0=SOT23-3N|MODELDATAFILEKIND0=PCBLib|MODELNAME=SOT23-3N|MODELTYPE=PCBLIB|	  
	    #print $d{'DESCRIPTION'}."\n" if(defined($d{'DESCRIPTION'}));
	  }
	  elsif($d{'RECORD'} =~m/^(44|46|47|48)$/)
	  {
	    # NOP
	  }
	  else
	  {
	    print "Unhandled Record type without: $d{RECORD}  (#$d{LINENO})\n";
	  }

      print OUT $dat unless(defined($d{'ISHIDDEN'}) && ($d{'ISHIDDEN'} eq 'T'));
	}

  }
  foreach my $part (sort keys %parts)
  {
    print OUT "\$Comp\n";
	#print "Reference: $part -> $globalreference{$part}\n";
	print OUT "L $partcomp{$part} ".($globalreference{$part}||"IC$ICcount")."\n"; # IC$ICcount\n";
	my $ts=uniqueid2timestamp($ICcount);
    print OUT "U 1 1 $ts\n";
    print OUT $_ foreach(@{$parts{$part}});
	print OUT "\t1    $xypos{$part}\n";
	my %orient=("0"=>"1    0    0    -1","3"=>"0    1    1    0","2"=>"-1   0    0    1","1"=>"0    -1   -1   0",
	            "4"=>"-1    0    0    -1","5"=>"0    -1    1    0","6"=>"1   0    0    1","7"=>"0    1   -1   0");
		
	print OUT "\t".$orient{$partorientation{$part}}."\n";
	print OUT "\$EndComp\n";
	$ICcount++;
  }  
  
  foreach my $component (sort keys %componentdraw)
  {
    my $comp="#\n# $component\n#\nDEF $component IC 0 40 Y Y 1 F N\n";
	$comp.="F0 ".($designatorpos{$component}||"\"IC\" 0 0 60 H V C CNN")."\n";
    $comp.="F1 ".($commentpos{$component}||"\"XC6SLX9-2CSG324C_1\" 0 0 60 H V C CNN")."\n";
    $comp.="F2 \"\" 0 0 60 H V C CNN\n";
    $comp.="F3 \"\" 0 0 60 H V C CNN\n";
    $comp.="DRAW\n";
	$comp.=$componentdraw{$component};
	$comp.="ENDDRAW\nENDDEF\n";
	$globalcomp.=$comp unless(defined($globalcontains{$component}));
	$globalcontains{$component}=1;
	print LIB $comp;
  }
  
  print OUT "\$EndSCHEMATC";
  close OUT;
  close LOG if($USELOGGING);
  print LIB "#End Library\n";
  close LIB;
}

foreach my $lib(sort keys %rootlibraries)
{
  #print "Rewriting Root Library $lib\n";
  open LIB,">$lib";
  my $timestamp=strftime "%d.%m.%Y %H:%M:%S", localtime;
  print LIB "EESchema-LIBRARY Version 2.3  Date: $timestamp\n#encoding utf-8\n";
  print LIB $globalcomp;
  print LIB "#End Library\n";
  close LIB;
}
