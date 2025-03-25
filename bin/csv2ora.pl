#!/usr/bin/env perl 
#
# "csv2ora.pl"
#
# Créer à partir d'un fichier *csv 
#  - un script de création de table
#  - le fichiers SQLLDR associés. 
#
# Usage:
#   gen_ddl_from_csv.pl <SCHEMA> <DB NAME> <TABLE_PREFIX> <fichier *.csv>
#
# Où: 
#  - <SCHEMA>         Est le schema dans lequel la table sera créée
#  - <DB NAME>        Database cible. Utilisé uniquement our afficher la commande sqlldr
#  - <TABLE_PREFIX>   Pour préfixer afin de mieux regrouper des tables. Sinon, donner "". 
#  - <fichier *.csv>  Fichier de départ. 
#     - Un acronyme est généré à partir du nom du fichier *.csv. 
#       Cet acronyme est utilisé dans les colonnes et pour nommer l'index de la PK. 
#     - Les en-têtes de colonnes deviennent noms de colonnes, préfixés de l'acronyme. 
#     - Quelque colonnes supplémentaires sont szstématiquement ajoutés. 
#       La table résultante est constituée comme suit: 
#
#       Table: [<PREFIXE>] + <nom formaté du fichier *.csv>
#
#           .------------------------------------------------------------.
#           | Colonne     | data Type        | Dafault | Contenu         | 
#           |-------------|------------------|---------|-----------------|
#           | *_ID        | INTEGER          |         | PK Séquence     | 
#        /->  *_col 1     | VARCHAR2(data)   |         | (col. 1 *.csv)  |
#  DATA   ->  *_col ..    | VARCHAR2(data)   |         | (col...  .csv)  |
#        \->  *_col n     | VARCHAR2(data)   |         | (col. n *.csv)  |
#           | *_ACT_FLG   | INTEGER          | 1       | Flag "Actif"    |
#           | *_VLD_FLG   | INTEGER          | 1       | Flag "Valide"   |
#           | *_CREATE_BY | VARCHAR(12 CHAR) |         | auteur insertion|
#           | *_CREATE_DT | DATE             | SYSDATE | date   insertion|
#           | *_UPDATE_BY | VARCHAR(12 CHAR) |         | auteur m.à.j.   |
#           | *_UPDATE_DT | DATE             |         | date   m.à.j.   |
#           '------------------------------------------------------------`
# 
# Author: Olaf AHLERS, 2006
# Modifications:
#    20120315 - OLS: posé ce script
# -----------------------------------------------------------------------------------------

use warnings;
use strict;
use File::Basename;
use Getopt::Long;

my %opts;
GetOptions(\%opts
            ,'suppress=s'
            ,'suppkey=s'
            ,'tab_pre=s'
          );
my $script = basename($0);
my $hr = {};
my ($tab_o, $db_n, $tab_pre) = (shift, shift, shift);
my $acro;
my $infile = shift or die "\n\tUsage:\n\n\t\t$script <SCHEMA> <DB NAME> <TABLE_PREFIX> <fichier *.csv>\n\n";

my %h_std_filters = (
   "QualiParc" => "(GRAPHIQUE|RIETAIRE|NEMENT|NATION|ION|ANCE)"
);

# ------------------------------------------------------------------------------
# ouvrir le fichier
#
open (my $INFILE, "<$infile") or die "Dog$!\n";
( my $nom_t = $infile ) =~ s/[\W]/_/g ;


$nom_t =~ s/_CSV\Z//i;
$nom_t = length($tab_pre) ? uc($tab_pre) . "_" . uc($nom_t) : uc($nom_t);

my $tab_n_len_limit = 30 - length($tab_pre . "_");
while (length($nom_t) > $tab_n_len_limit) {
    print "
    Nom \"$nom_t\" trop long.
    Enlever ", length($nom_t) - $tab_n_len_limit, " charactères

    => ";
    $nom_t = <STDIN>;
    chomp $nom_t;
    length($nom_t) or die "(abandon)";
}

# ------------------------------------------------------------------------------
# dériver l'acronyme du nom de la table
#
my $argo   = $nom_t;
if ($argo =~ /_/ ) {
    print "composable\n";
    $acro .= substr($argo, 0, 1);
    my $cnt = 0;
    while ($argo =~ s/[^_]+_// && ++$cnt < 4) {
        $acro .= substr($argo, 0, 1);
    }
} else {
    print "simple\n";
    $acro .= substr($argo, 0, 3);
}
$acro =~ s/[0-9]//g;
my $PK = $acro . "_ID";

my $nom_sql = $nom_t . ".SQL";
open (my $NOM_SQL, ">$nom_sql") or die "Dog$!\n";

my $nom_ctl = $nom_t . ".CTL";
open (my $NOM_CTL, ">$nom_ctl") or die "Dog$!\n";

my $nom_dat = $nom_t . ".DAT";
open (my $NOM_DAT, ">$nom_dat") or die "Dog$!\n";

my $nom_bad = $nom_t . ".BAD";

# ------------------------------------------------------------------------------
# say something
#
print "lire $infile ..\n";

# ------------------------------------------------------------------------------
# initialiser le hash $hr avec les column headers. 
#
   my $headline = (<$INFILE>);
   chomp $headline;
   $headline =~ s///g;
   $headline =~ s/[\|\"\']//g;
   if ($opts{suppress}) {
       print "applique s/$opts{suppress}//g (noms de colonnes)\n";
       $headline    =~ s/$opts{suppress}//g;
       print "purge zarb chars: s/^[_A-Za-z0-9]+/_/g (noms de colonnes)\n";
       $headline    =~ s/[^,_A-Za-z0-9]+/_/g;
   }
   if ($opts{suppkey}) {
       print "applique s/$h_std_filters{$opts{suppkey}}//gi (noms de colonnes)\n";
       $headline    =~ s/$h_std_filters{$opts{suppkey}}//gi;
   }
   
   my $ar_head = [];
   @{$ar_head} = (split /,/, $headline);
   my $maxheadwidth = 1;
   my $cnt = 0;
   foreach my $colhead (@{$ar_head}) {
       $colhead =~ s/^_//;
       $colhead = $acro . "_" . $colhead;   # prefix column header
       $ar_head->[$cnt++] = $colhead;       # update array with new column name
       $hr->{$colhead}->{LENGHT}=1;
       # # #     $hr->{$colhead}->{DATA} = [];
       $maxheadwidth < length($colhead) and 
       $maxheadwidth = length($colhead);
   }

# ------------------------------------------------------------------------------
# mesurer la length de chaque piece of data
#
   my $cnt_rows = 0;
   foreach my $data_set (<$INFILE>) { 
       chomp $data_set;
       no warnings;
       $data_set =~ s/\s*,\s*/,/g;
       next if $data_set =~ m/^,*\s*$/;
       my @a_data_set = (split /,/, $data_set);
       my $cnt_items = 0;
       foreach my $colhead (@{$ar_head}) {
           # # # push @ {$hr->{$colhead}->{DATA}}, ($a_data_set[$cnt_items]);
           $hr->{$colhead}->{LENGHT} < length($a_data_set[$cnt_items]) and
           $hr->{$colhead}->{LENGHT} = length($a_data_set[$cnt_items]);
           ++$cnt_items;
       }
       print $NOM_DAT ++$cnt_rows, ",", $data_set, "\n";
   }

# ------------------------------------------------------------------------------
# printer le fichier *.SQL
#
   print STDOUT "genere $nom_sql\n";
   my $comma = ",";  # le comma est comma depuis le debut, car la PK precede tout le set
   $maxheadwidth += 3;
   select $NOM_SQL;
   printf "CREATE TABLE $nom_t (\n      %-${maxheadwidth}s INTEGER\n", $PK;
   foreach my $colhead (@{$ar_head}) {
       printf "    %s %-${maxheadwidth}s VARCHAR2(%d CHAR)\n",  $comma, $colhead, $hr->{$colhead}->{LENGHT};
       $comma = ",";
   }
   printf "    %s %-${maxheadwidth}s INTEGER DEFAULT 1\n"   ,  $comma, $acro . "_ACT_FLG";
   printf "    %s %-${maxheadwidth}s INTEGER DEFAULT 1\n"   ,  $comma, $acro . "_VLD_FLG";
   printf "    %s %-${maxheadwidth}s VARCHAR2(%d CHAR)\n"   ,  $comma, $acro . "_CREATE_BY", 10;
   printf "    %s %-${maxheadwidth}s DATE DEFAULT SYSDATE\n",  $comma, $acro . "_CREATE_DT";
   printf "    %s %-${maxheadwidth}s VARCHAR2(%d CHAR)\n"   ,  $comma, $acro . "_UPDATE_BY", 10;
   printf "    %s %-${maxheadwidth}s DATE\n"                ,  $comma, $acro . "_UPDATE_DT";
   print ");\n";
   print "CREATE UNIQUE INDEX ${acro}_PK on $nom_t($PK);\n";
   print "ALTER TABLE $nom_t add primary key ($PK);\n";
  

# ------------------------------------------------------------------------------
# printer le fichier *.CTL
#
   print STDOUT "genere $nom_ctl\n";
   $comma = ",";
   select $NOM_CTL;
   print "LOAD DATA\n";
   print "INFILE '$nom_dat'\n";
   print "BADFILE '$nom_bad'\n";
   print "APPEND\n";
   print "INTO TABLE $nom_t\n";
   print "FIELDS TERMINATED BY \",\"\n";
   print "TRAILING NULLCOLS\n";
   print "(\n     $PK\n";
   foreach my $colhead (@{$ar_head}) {
       printf "    %s%s\n",  $comma, $colhead;
       $comma = ",";
   }
   print ")\n";

select STDOUT;
print "Create archive ..\n";
system "tar -cvf - $nom_sql $nom_ctl $nom_dat|gzip -c > $infile.sqlldr.tgz\n";
print "\nscp $ENV{USER}@$ENV{HOSTNAME}:$ENV{PWD}/$infile.sqlldr.tgz .\n\n";

print "gunzip -c $infile.sqlldr.tgz | tar -xmvf -\n";
print "sqlplus $tab_o\@$db_n \@$nom_sql\n";
print "quit\n";
print "sqlldr $tab_o\@$db_n control=$nom_ctl\n";

# ------------------------------------------------------------------------------
# cleanup
#
   close $INFILE;
   close $NOM_SQL;
   close $NOM_CTL;

