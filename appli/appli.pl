#!/usr/bin/perl
# -*- encoding: utf-8; indent-tabs-mode: nil -*-
#
#
#     Application interactive pour isoler et reconnaître les caractères dans une série de documents
#     Interactive app to isolate and recognise chars in a set of documents
#     Copyright (C) 2017 Jean Forget
#
#     Voir la licence dans la documentation incluse ci-dessous.
#     See the license in the embedded documentation below.
#

use v5.10;
use strict;
use warnings;
use Dancer2;
use MongoDB;
use YAML;
use GD;
use MIME::Base64;
use DateTime;
use experimental qw/switch/;

set 'session' => 'Simple';

get '/' => sub {
  return <<'EOF'
<html>
<head>
<title>Login</title>
</head>
<body>
<form action='/accueil' method='post'>
Appli&nbsp;: <input type='text' name='appli' />
<br />
Mot de passe&nbsp;: <input type='password' name='password' />
<br /><input type='submit' value='login' />
</form>
</body>
</html>
EOF
};

post '/accueil' => sub {
  my $appli = body_parameters->get('appli');
  my $mdp   = body_parameters->get('password');
  #say "appli= $appli";
  set 'username' => $appli;
  set 'password' => $mdp;
  verif_glyphe_espace($appli, $mdp);
  redirect '/listedoc';
};


any [ 'get', 'post' ] => '/listedoc' => sub {
  my $appli     = setting('username');
  my $mdp       = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $liste_ref = liste_doc($appli, $mdp);
  return aff_liste($appli, $mdp,'', '', '', $liste_ref);
};

post '/credoc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc = body_parameters->get('document');
  my $fic = body_parameters->get('fichier');
  my $msg = credoc($appli, $mdp, $doc, $fic);
  if ($msg) {
    return aff_liste($appli, $mdp, $doc, $fic, $msg, liste_doc($appli, $mdp));
  }
  #say "création du document $doc, basé sur le fichier $fic";

  redirect '/listedoc';
};

get '/doc/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_doc($appli, $mdp, $doc, 'base');
};

get '/grille/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_doc($appli, $mdp, $doc, 'grille');
};

post '/majgrille/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  my %param;
  unless ($appli) {
    redirect '/';
  }
  for my $par (qw/x0 y0 dx dy dirh cish dirv cisv/) {
    $param{$par} = body_parameters->get($par);
  }
  my $doc   = route_parameters->get('doc');
  $param{doc} = $doc;
  #say YAML::Dump({ %param });
  my $msg = maj_grille($appli, $mdp, { %param });
  #say "Mise à jour de la grille pour $doc";
  redirect "/grille/$doc";
};

post '/valgrille/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "Validation de la grille pour $doc";
  my $msg = val_grille($appli, $mdp, $doc);
  redirect "/grille/$doc";
};

post '/association/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "Générationdes associations pour $doc";
  my $msg = association($appli, $mdp, $doc, -1, -1);
  redirect "/grille/$doc";
};

post '/generation/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  #say "Génération du texte pour $doc";
  my $msg = generation($appli, $mdp, $doc);
  redirect "/grille/$doc";
};

get '/cellule/:doc/:l/:c' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  my $l     = route_parameters->get('l');
  my $c     = route_parameters->get('c');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_cellule($appli, $mdp, $doc, $l, $c);
};

post '/creglyphe/:doc/:l/:c' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $car = body_parameters->get('caractere');
  my $doc = route_parameters->get('doc');
  my $l   = route_parameters->get('l');
  my $c   = route_parameters->get('c');
  #say "Création d'un glyphe pour $car à l'image de la cellule $doc $l $c";
  my $msg = copie_cel_gly($appli, $mdp, $doc, $l, $c, $car);
  redirect "/cellule/$doc/$l/$c";
};

post '/assocglyphe/:doc/:l/:c' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc = route_parameters->get('doc');
  my $l   = route_parameters->get('l');
  my $c   = route_parameters->get('c');
  #say "Générationdes associations pour $doc $l $c";
  my $msg = association($appli, $mdp, $doc, $l, $c);
  redirect "/cellule/$doc/$l/$c";
};

get '/coloriage/:doc/:n' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  my $n     = route_parameters->get('n');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_coloriage($appli, $mdp, $doc, $n);
};

post '/majcolor/:doc/:n' => sub {
  #say "crecolor";
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }

  my %param;
  my $action;
  my $doc   = route_parameters->get('doc');
  my $n     = route_parameters->get('n');
  if ($n eq 'nouveau') {
    my $liste = liste_coloriage($appli, $mdp, $doc);
    $n = 0;
    for my $col (@$liste) {
      $n = $col->{n} if $n <= $col->{n};
    }
    $n++;
    $param{doc}    = $doc;
    $param{n}      = 0 + $n;
    $param{dh_cre} = horodatage();
    $action        = 'cre';
  }
  else {
    $param{dh_maj} = horodatage();
    $action        = 'maj';
  }

  my @critere = ();
  for my $i (0..5) {
    my $critere = {};
    for my $par (qw/select seuil caract selspace/) {
      $critere->{$par} = body_parameters->get("$par$i") // '';
    }
    $critere->{seuil} = 0 + $critere->{seuil};
    push @critere, $critere;
  }
  $param{criteres} = [ @critere ];

  #say "Mise à jour du coloriage pour $doc";
  #say YAML::Dump({ %param });

  my $msg;
  if ($action eq 'cre') {
    #say "création n = $n";
    $msg = ins_coloriage($appli, $mdp, $doc, $n, { %param });
  }
  else {
    $msg = maj_coloriage($appli, $mdp, $doc, $n, { %param });
  }

  #say "Mise à jour du coloriage pour $doc";
  redirect "/coloriage/$doc/$n";
};

start;

sub liste_doc {
  my ($appli, $mdp) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Document");
  my $doc    = $coll->find;
  #say YAML::Dump($doc);
  my @liste = $doc->all;
  return [ @liste ];
}

sub get_doc {
  my ($appli, $mdp, $doc) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Document");
  my $obj    = $coll->find_one({ doc => $doc });
  # say YAML::Dump($obj);
  return $obj;
}

sub ins_doc {
  my ($appli, $mdp, $doc) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Document");
  my $res    = $coll->insert_one($doc);
}

sub maj_doc {
  my ($appli, $mdp, $doc, $val) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Document");
  my $result = $coll->update({ doc => $doc }, { '$set' => $val });
  return $result;
}

sub get_cellule {
  my ($appli, $mdp, $doc, $l, $c) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Cellule");
  my $obj    = $coll->find_one({ doc => $doc, l => 0 + $l, c => 0 + $c });
  #my $obj    = $coll->find_one({ doc => $doc});
  #say "recherche $doc $l $c";
  #say YAML::Dump($obj);
  return $obj;
}

sub iter_cellule {
  my ($appli, $mdp, $critere) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Cellule");
  my $iter   = $coll->find($critere);
  return $iter
}

sub ins_many_cellule {
  my ($appli, $mdp, $tab_cell) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Cellule");
  my $result = $coll->insert_many($tab_cell);
  return $result;
}

sub maj_cellule {
  my ($appli, $mdp, $doc, $l, $c, $val) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Cellule");
  my $result = $coll->update({ doc => $doc, l => 0 + $l, c => 0 + $c }, { '$set' => $val });
  return $result;
}

sub purge_cellule {
  my ($appli, $mdp, $doc) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Cellule");
  my $result = $coll->remove({ doc => $doc });
  return $result;
}

sub stat_cellule {
  my ($appli, $mdp, $doc) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Cellule");
  my $result = $coll->aggregate( [ { '$match' => { 'doc' => $doc } },
                                   { '$group' => { '_id' => '$doc',
                                                   'nb'    => { '$sum' => 1 },
                                                   'maxsc' => { '$max' => '$score' },
                                                   'moysc' => { '$avg' => '$score' },
                                     } } ] );
  #say YAML::Dump($result);
  return $result;
}

sub iter_glyphe {
  my ($appli, $mdp) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Glyphe");
  my $iter   = $coll->find({  });
  return $iter
}

sub get_glyphe {
  my ($appli, $mdp, $car, $num) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Glyphe");
  my $obj    = $coll->find_one({ car => $car, num => 0 + $num });
  #say YAML::Dump($obj);
  return $obj;
}

sub get_glyphe_1 {
  my ($appli, $mdp, $car1, $num) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Glyphe");
  my $obj    = $coll->find_one({ car1 => $car1, num => 0 + $num });
  #say YAML::Dump($obj);
  return $obj;
}

sub ins_glyphe {
  my ($appli, $mdp, $obj) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Glyphe");
  $coll->insert_one($obj);
  #say YAML::Dump($obj);
  return $obj;
}

sub glyphe_max_1 {
  my ($appli, $mdp, $car1) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Glyphe");
  my $result = $coll->aggregate( [ { '$match' => { 'car1' => $car1 }},
                                   { '$group' => { '_id' => '$car1', 'hnum' => { '$max' => '$num' }}} ] );
  my $num= $result->{_docs}[0]{hnum} // 0;
  #say YAML::Dump($result);
  return $num;
}

sub liste_coloriage {
  my ($appli, $mdp, $doc) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Coloriage");
  my $iter   = $coll->find({ doc => $doc });
  my @liste   = $iter->all();
  return [ @liste ];
}

sub get_coloriage {
  my ($appli, $mdp, $doc, $n) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Coloriage");
  my $obj    = $coll->find_one({ doc => $doc, n => 0 + $n });
  #my $obj    = $coll->find_one({ doc => $doc});
  #say "recherche $doc $l $c";
  #say YAML::Dump($obj);
  return $obj;
}

sub ins_coloriage {
  my ($appli, $mdp, $doc, $n, $val) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Coloriage");
  $val->{doc} = $doc;
  $val->{n}   = 0 + $n;
  my $res    = $coll->insert_one($val);
}

sub maj_coloriage {
  my ($appli, $mdp, $doc, $n, $val) = @_;
  my $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
  my $coll   = $client->ns("$appli.Coloriage");
  my $result = $coll->update({ doc => $doc, n => 0 + $n }, { '$set' => $val });
  return $result;
}

sub verif_glyphe_espace {
  my ($appli, $mdp) = @_;
  my $obj = get_glyphe_1($appli, $mdp, 'SP', 1);
  unless ($obj) {
    #$obj = { car => ' ', car1 => 'SP', num => 1, dh_cre = horodatage() };
    my $image = GD::Image->new(2,2);
    my $blanc = $image->colorAllocate(255, 255, 255);
    ins_glyphe($appli, $mdp, { car       => ' ',
                               car1      => 'SP',
                               num       =>  1,
                               dh_cre    => horodatage(),
                               lge       =>  2,
                               hte       =>  2,
                               nb_noir   =>  0,
                               ind_noir  => -1, # -1 parce qu'il n'y a pas de noir et que colorExact renvoie -1
                               ind_blanc =>  0,
                               data      => encode_base64($image->png) } );
  }
  return $obj;
}

sub copie_cel_gly {
  my ($appli, $mdp, $doc, $l, $c, $car1) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);

  my $car;
  if ($car1 eq 'SP') {
    $car = ' ';
  }
  else {
    $car = $car1;
  }

  my $info_cellule = get_cellule($appli, $mdp, $doc, $l, $c);

  my $num = 1 + glyphe_max_1($appli, $mdp, $car1);
  ins_glyphe($appli, $mdp, { car       => $car,
                             car1      => $car1,
                             num       => $num,
                             dh_cre    => horodatage(),
                             lge       => $info_cellule->{lge},
                             hte       => $info_cellule->{hte},
                             nb_noir   => $info_cellule->{nb_noir},
                             ind_noir  => $info_cellule->{ind_noir},
                             ind_blanc => $info_cellule->{ind_blanc},
                             data      => $info_cellule->{data},
                             dh_cre    => horodatage(),
                           } );
  my $result = maj_cellule($appli, $mdp, $doc, $l, $c, { score    => 0,
                                                         nb_car   => 1,
                                                         glyphes  => [ { car => $car, num => $num } ],
                                                         cpt_car  => { $car1 => 1 },
                                                         dh_assoc => horodatage(),
                                                       });
}

sub credoc {
  my ($appli, $mdp, $doc, $fic) = @_;
  if ($doc !~ /^\w+$/) {
    return "Le nom du document contient des caractères interdits. Seuls les caractères alphanumériques sont autorisés.";
  }
  if ($fic !~ /\.png$/) {
    return "Seuls les fichiers .png sont autorisés";
  }
  if ($fic !~ /^\w+\.png$/) {
    return "Le nom de fichier contient des caractères interdits. Seuls les caractères alphanumériques sont autorisés, ainsi qu'un point pour délimiter l'extension.";
  }
  my %obj = ( doc => $doc, fic => $fic, dx => 30, dy => 50, cish => 0, cisv => 0, etat => 1 );

  my $image = GD::Image->newFromPng($fic);
  my ($l, $h) = $image->getBounds();
  $obj{taille_x} = $l;
  $obj{taille_y} = $h;
  my @cpt = (0, 0);
  my @xmin = (1e99, 1e99);
  my @ymin = (1e99, 1e99);
  for my $x (0 .. $h - 1) {
    for my $y (0 .. $l - 1) {
      my $index  = $image->getPixel($x, $y);
      $cpt[$index]++;
      $xmin[$index] = $x if $xmin[$index] > $x;
      $ymin[$index] = $y if $ymin[$index] > $y;
    }
  }
  # heuristique : pour un Document, les pixels nois sont beaucoup moins nombreux que les blancs
  # (pour les Glyphes, ce n'est pas forcément la même chose)
  if ($cpt[0] < $cpt[1]) {
    $obj{ind_blanc} = 1;
    $obj{ind_noir}  = 0;
  }
  else {
    $obj{ind_blanc} = 0;
    $obj{ind_noir}  = 1;
  }
  $obj{nb_noirs} = $cpt[$obj{ind_noir}];
  $obj{x0}       = $xmin[$obj{ind_noir}];
  $obj{y0}       = $ymin[$obj{ind_noir}];
  $obj{dh_cre}   = horodatage();

  ins_doc($appli, $mdp, { %obj });
  return '';
}

sub maj_grille {
  my ($appli, $mdp, $ref_param) = @_;
  my $doc      = $ref_param->{doc};

  my $info_doc = get_doc($appli, $mdp, $doc);
  #say YAML::Dump( $info_doc );

  my $fichier = $info_doc->{fic};
  $fichier =~ s/\.png$/-grille.png/;
  $ref_param->{grille} = $fichier;

  purge_cellule    ($appli, $mdp, $doc);
  construire_grille($appli, $mdp, $info_doc, $ref_param, 0);

  $ref_param->{dh_grille} = horodatage();
  $ref_param->{grille}    = $fichier;
  $ref_param->{etat}      = 2;
  my $result = maj_doc($appli, $mdp, $doc, $ref_param);

  return '';
}

sub val_grille {
  my ($appli, $mdp, $doc) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);

  purge_cellule    ($appli, $mdp, $doc);
  my @cellule = construire_grille($appli, $mdp, $info_doc, $info_doc, 1);

  my $ref_param;
  $ref_param->{dh_valid}  = horodatage();
  $ref_param->{etat}      = 3;
  maj_doc         ($appli, $mdp, $doc, $ref_param);
  purge_cellule   ($appli, $mdp, $doc);
  ins_many_cellule($appli, $mdp, [ @cellule ] );
}

sub construire_grille {
  my ($appli, $mdp, $info_doc, $ref_param, $flag) = @_;

  my @cellule;

  my $image = GD::Image->newFromPng($info_doc->{fic});
  my $rouge = $image->colorAllocate(255,   0,   0);
  my $vert  = $image->colorAllocate(  0, 255,   0);
  my $bleu  = $image->colorAllocate(  0,   0, 255);

  my $noir    = $info_doc->{ind_noir};
  my $x0      = $ref_param->{x0};
  my $y0      = $ref_param->{y0};
  my $dx      = $ref_param->{dx};
  my $dy      = $ref_param->{dy};
  my $coef_cx = $ref_param->{dx};
  my $coef_ly = $ref_param->{dy};
  my $coef_lx = 0;
  my $coef_cy = 0;
  if ($ref_param->{cish}) {
    if ($ref_param->{dirh} eq 'gauche') {
      $coef_lx = -1 / $ref_param->{cish};
    }
    else {
      $coef_lx = 1 / $ref_param->{cish};
    }
  }
  if ($ref_param->{cisv}) {
    if ($ref_param->{dirv} eq 'haut') {
      $coef_cy = -1 / $ref_param->{cisv};
    }
    else {
      $coef_cy = 1 / $ref_param->{cisv};
    }
  }
  #say "horizontal $ref_param->{cish}, vertical $ref_param->{cisv}";
  #say "coef lx = $coef_lx, ly = $coef_ly, cx = $coef_cx, cy = $coef_cy";

  my $l_max = int(($info_doc->{taille_y} - $y0) / $coef_ly);
  my $c_max = int(($info_doc->{taille_x} - $x0) / $coef_cx);
  for my $l (0..$l_max) {
    for my $c (0..$c_max) {
      my $x = int($x0 + $coef_cx * $c + $coef_lx * $l);
      my $y = int($y0 + $coef_cy * $c + $coef_ly * $l);
      my $couleur;

      # Dessin de la cellule dans la grille
      if ($flag == 0) {
        if (($l + $c) % 2) {
          $couleur = $bleu;
        }
        else {
          $couleur = $vert;
        }
        for my $x1 (0,   $dx) {
          for my $y1 (0 .. $dy) {
            my $pixel = $image->getPixel($x +$x1, $y + $y1);
            if ($pixel == $noir) {
              $image->setPixel($x + $x1, $y + $y1, $rouge);
            }
            else {
              $image->setPixel($x + $x1, $y + $y1, $couleur);
            }
          }
        }
        for my $x1 (0 .. $dx) {
          for my $y1 (0,   $dy) {
            my $pixel = $image->getPixel($x +$x1, $y + $y1);
            if ($pixel == $noir) {
              $image->setPixel($x + $x1, $y + $y1, $rouge);
            }
            else {
              $image->setPixel($x + $x1, $y + $y1, $couleur);
            }
          }
        }
      }

      # Extraction de la cellule
      if ($flag == 1) {
        # Compter les pixels noirs et repérer le plus haut, le plus bas,
        # le plus à gauche et le plus à droite
        my $nb_noir = 0;  
        my ($xmin, $xmax, $ymin, $ymax) = ($dx, 0, $dy, 0);
        for my $x1 (0 .. $dx) {
          for my $y1 (0 .. $dy) {
            my $pixel = $image->getPixel($x +$x1, $y + $y1);
            if ($pixel == $noir) {
              $nb_noir++;
              $xmin = $x1 if $xmin > $x1;
              $xmax = $x1 if $xmax < $x1;
              $ymin = $y1 if $ymin > $y1;
              $ymax = $y1 if $ymax < $y1;
            }
          }
        }
        # Ne pas extraire les cellules avec que du blanc
        if ($nb_noir) {
          # L'enveloppe des pixels noirs
          my $lg_env = $xmax - $xmin + 1;
          my $ht_env = $ymax - $ymin + 1;
          my $cellule = GD::Image->new($lg_env, $ht_env);
          $cellule->copy($image, 0, 0, $x + $xmin, $y + $ymin, $lg_env, $ht_env);

          # Le voisinage : la cellule et les 24 cellules environnantes
          my $x25 = $x - 2 * $dx;
          my $y25 = $y - 2 * $dy;
          if ($x25 < 0) {
            $x25 = 0;
          }
          elsif ($x25 > $info_doc->{taille_x}) {
            $x25 = $info_doc->{taille_x};
          }
          if ($y25 < 0) {
            $y25 = 0;
          }
          elsif ($y25 > $info_doc->{taille_y}) {
            $y25 = $info_doc->{taille_y};
          }
          my $voisinage = GD::Image->new(5 * $dx, 5 * $dy); 
          $voisinage->copy($image, 0, 0, $x25, $y25, 5 * $dx, 5 * $dy); 

          my $info_cellule = { doc     => $info_doc->{doc},
                               dh_cre  => horodatage(),
                               # coordonnées de la cellule
                               l       => $l,
                               c       => $c,
                               xc      => $x,
                               yc      => $y,
                               # enveloppe des pixels noirs
                               xe        => $xmin,
                               ye        => $ymin,
                               lge       => $lg_env,
                               hte       => $ht_env,
                               # graphisme
                               ind_noir  => $cellule->colorExact(  0,   0,   0),
                               ind_blanc => $cellule->colorExact(255, 255, 255),
                               nb_noir   => $nb_noir,
                               data      => encode_base64($cellule->png),
                               voisin    => encode_base64($voisinage->png),
                             };
          # calcul du score
          my ($score, $liste_glyphes, $cpt_car) = score_cel($appli, $mdp, $info_doc->{doc}, $info_cellule);
          $info_cellule->{score}    = $score;
          $info_cellule->{glyphes}  = $liste_glyphes;
          $info_cellule->{cpt_car}  = $cpt_car;
          $info_cellule->{nb_car}   = 0 + keys %$cpt_car;
          $info_cellule->{dh_assoc} = horodatage();
          push @cellule, $info_cellule;
        }
                
      }
    }
  }
  if ($flag == 0) {
    my $fichier = $ref_param->{grille};
    open my $im, '>', $fichier
      or die "Ouverture $fichier $!";
    print $im $image->png;
    close $im
      or die "Fermeture $fichier $!";
  }
  return @cellule;
}


sub association {
  my ($appli, $mdp, $doc, $l, $c) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);
  my $critere = { doc => $doc };
  if ($l >= 0) {
    # Lancement pour une seule Cellule
    $critere->{l} = 0 + $l;
    $critere->{c} = 0 + $c;
  }
  #say YAML::Dump($critere);
  my $iter = iter_cellule($appli, $mdp, $critere);
  while (my $info_cellule = $iter->next) {
    # calcul du score
    #say "calcul du score l = $info_cellule->{l}, c = $info_cellule->{c}";
    my ($score, $liste_glyphes, $cpt_car) = score_cel($appli, $mdp, $info_doc->{doc}, $info_cellule);
    my $val = { score    => $score, 
                nb_car   => 0 + keys %$cpt_car,
                glyphes  => $liste_glyphes,
                cpt_car  => $cpt_car,
                dh_assoc => horodatage(),
              };
    my $result = maj_cellule($appli, $mdp, $doc, $info_cellule->{l}, $info_cellule->{c}, $val);
  }
  if ($l < 0) {
    # Lancement pour tout le document
    my $ref_param;
    $ref_param->{dh_assoc}  = horodatage();
    $ref_param->{etat}      = 4;
    maj_doc($appli, $mdp, $doc, $ref_param);
  }
}

sub generation {
  my ($appli, $mdp, $doc) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);

  my @ligne = ();
  my $critere = { doc => $doc };
  my $iter = iter_cellule($appli, $mdp, $critere);
  while (my $info_cellule = $iter->next) {

    my $l       = $info_cellule->{l};
    my $c       = $info_cellule->{c};
    my $glyphe  = shift @{ $info_cellule->{glyphes} }; # Tant pis s'il y a plusieurs Glyphes associés à la Cellule
    my $car     = $glyphe->{car};

    # initialisaton du tableau des lignes
    $ligne[$l] //= '';
    my $long    = length($ligne[$l]);

    #say "ligne $l, insérer '$car' en colonne $c";
    if ($c < length($ligne[$l])) {
      substr($ligne[$l], $c, 1) = $car;
    }
    else {
      # Il faut étendre la ligne. Supposons qu'elle fasse 3 caractères de
      # long (colonnes 0 à 2) et que l'on ajoute un nouveau caractère en colonne 6
      # (longueur résultante 7). Il faut donc ajouter 3 espaces plus le caractère.
      $ligne[$l] .= ' ' x ($c - $long) . $car;
    }

  }

  # Des fois qu'une ligne ne contienne rien du tout, aucune Cellule
  for my $l (0 .. $#ligne) {
    $ligne[$l] //= '';
  }

  my $fic = "$doc.txt";
  open my $fh, '>', $fic
    or die "ouverture $fic : $!";
  for (@ligne) {
    say $fh $_;
  }
  close $fh
    or die "fermeture $fic : $!";

  # Mise à jour du document
  maj_doc($appli, $mdp, $doc, { txt      => $fic,
                                etat     => 5,
                                dh_gener => horodatage(),
                              });
}

sub aff_liste {
  my ($appli, $mdp, $doc, $fic, $msg, $liste_ref) = @_;

  # Élimination des caractères dangereux
  $doc =~ s/(\W)/'&#' . ord($1) . ';'/eg;
  $fic =~ s/([^.\w])/'&#' . ord($1) . ';'/eg;

  # Valeurs facultatives
  if ($doc ne '') {
    $doc = " value='$doc'";
  }
  if ($fic ne '') {
    $fic = " value='$fic'";
  }
  if ($msg ne '') {
    $msg = "<br />$msg";
  }

  my $liste = '';
  for (@{$liste_ref}) {
    my $elem .= "<a href='/doc/$_->{doc}'>$_->{doc}</a>";
    if ($_->{etat} >= 2) {
      $elem .= " <a href='/grille/$_->{doc}'>grille</a>";
    }
    $liste .= "<li>$elem</li>\n";
  }

  return <<"EOF"
<html>
<head>
<title>Liste des documents</title>
<meta http-equiv='Content-Type' content='text/html; charset=UTF-8' />
</head>
<body>
Appli&nbsp;: $appli
<br />
<a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>
<h1>Nouveau document</h1>
<form action='/credoc' method='post'>
Document&nbsp;: <input type='text' name='document' $doc />
Fichier&nbsp;: <input type='text' name='fichier' $fic />
<br /><input type='submit' value='ajouter' />
</form>
$msg
<hr />
<h1>Documents existants</h1>
<ul>
$liste
</ul>
</body>
</html>
EOF
}

sub aff_doc {
  my ($appli, $mdp, $doc, $variante) = @_;
  my $info = get_doc($appli, $mdp, $doc);

  # Libellé bidon car les états commencent en 1
  my @etat = ('bidon', 'Créé', 'Grille définie', 'Grille validée', 'Conversion effectuée', 'Fichier texte généré');

  # Mise en forme du cisaillement horizontal
  my $droite = '';
  my $gauche = '';
  given ($info->{dirh}) {
    when ('droite') { $droite = "checked='1'"; }
    when ('gauche') { $gauche = "checked='1'"; }
  }

  # Mise en forme du cisaillement vertical
  my $haut = '';
  my $bas  = '';
  given ($info->{dirv}) {
    when ('haut'  ) { $haut   = "checked='1'"; }
    when ('bas'   ) { $bas    = "checked='1'"; }
  }

  # Quel fichier graphique faut-il afficher ?
  my $fichier;
  given ($variante) {
    when ('base'  ) { $fichier = $info->{fic}   ; }
    when ('grille') { $fichier = $info->{grille}; }
  }
  my $image = GD::Image->newFromPng($fichier);
  my $data  = encode_base64($image->png);

  my $maj_grille = '';
  if ($info->{etat} >= 2) {
    $maj_grille .= "<p>Mise à jour de la grille $info->{dh_grille} (UTC)</p>\n";
  }

  # Faut-il proposer la validation de la grille ?
  my $validation = '';
  if ($info->{etat} >= 2) {
    $validation = <<"EOF";
<h2>Validation de la grille</h2>
<form action='/valgrille/$info->{doc}' method='post'>
<br /><input type='submit' value='Validation' />
</form>
EOF
  }
  if ($info->{etat} >= 3) {
    $validation .= "<p>Grille validée le $info->{dh_valid} (UTC)</p>\n";
  }

  my $association = '';
  if ($info->{etat} >= 3) {
    $association  = <<"EOF";
<h2>Association des Cellules avec des Glyphes</h2>
<form action='/association/$info->{doc}' method='post'>
<br /><input type='submit' value='Lancer l association' />
</form>
EOF
  }
  if ($info->{etat} >= 4) {
    $association .= "<p>Association lancée le $info->{dh_assoc} (UTC)</p>\n";
  }
  if ($info->{etat} >= 3) {
    my $stat = stat_cellule($appli, $mdp, $doc);
    $stat = $stat->{_docs}[0];
    my $score_moyen = int($stat->{moysc} * 100) / 100;
    $association .= "<p>Nombre de cellules&nbsp;: $stat->{nb}, score maximal&nbsp;: $stat->{maxsc}, score moyen&nbsp;: $score_moyen</p>\n";
  }

  my $coloriage = '';
  if ($info->{etat} >= 3) {
    my $liste  =liste_coloriage($appli, $mdp, $doc);
    $coloriage = join ' ', map { sprintf "<a href='/coloriage/$doc/%d'>%d</a>", $_->{n}, $_->{n} } @$liste;
    $coloriage = <<"EOF";
<h2>Coloriages</h2>
<p>$coloriage <a href='/coloriage/$doc/nouveau'>nouveau</a></p>
EOF
  }

  my $generation = '';
  if ($info->{etat} >= 4) {
    $generation  = <<"EOF";
<h2>Génération du fichier texte</h2>
<form action='/generation/$info->{doc}' method='post'>
<br /><input type='submit' value='Lancer la génération' />
</form>
EOF
  }
  if ($info->{etat} >= 5) {
    $generation .= "<p>Génération du texte le $info->{dh_gener} (UTC)</p>\n";
  }
  

  return <<"EOF";
<html>
<head>
<title>Document $doc</title>
</head>
<body>
Appli&nbsp;: $appli
<br /><a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>

<h1>Document $doc</h1>
<p>$info->{taille_x} x $info->{taille_y} dont $info->{nb_noirs} pixels noirs.</p>
<p>$etat[ $info->{etat} ]</p>
<p>Création $info->{dh_cre} (UTC)</p>

<h2>Grille</h2>
<form action='/majgrille/$info->{doc}' method='post'>
Origine&nbsp;: x = <input type='text' name='x0' value='$info->{x0}' />, y = <input type='text' name='y0' value='$info->{y0}' />
<br />Taille des cellules&nbsp;: largeur <input type='text' name='dx' value='$info->{dx}' /> hauteur <input type='text' name='dy' value='$info->{dy}' />
<br />Cisaillement horizontal&nbsp: 1 pixel vers la <input type='radio' name='dirh' value='gauche' $gauche >gauche
                                                    <input type='radio' name='dirh' value='droite' $droite >droite toutes les <input type='text' name='cish' value='$info->{cish}' /> lignes
<br />Cisaillement vertical&nbsp: 1 pixel vers le <input type='radio' name='dirv' value='haut' $haut >haut
                                                  <input type='radio' name='dirv' value='bas'  $bas  >bas tous les <input type='text' name='cisv' value='$info->{cisv}' /> caractères
<br /><input type='submit' value='grille' />
</form>
$maj_grille
$validation
$association
$coloriage
$generation
<img src='data:image/png;base64,$data' alt='document $doc' />
</body>
</html>
EOF
};

sub aff_cellule {
  my ($appli, $mdp, $doc, $l, $c) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);
  my $info_cellule = get_cellule($appli, $mdp, $doc, $l, $c);

  my $html;
  if ($info_cellule) {
    my $voisinage = $info_cellule->{voisin};

    my $cre_glyphe = '';
    if ($info_cellule->{score} != 0) {
      $cre_glyphe = <<"EOF";
<h3>Création de glyphe</h3>
<form action='/creglyphe/$doc/$l/$c' method='post'>
Caractère (ou 'SP' pour espace) <input type='text' name='caractere' />
<input type='submit' value='Créer glyphe' />
</form>
EOF
    }

    my $assoc_glyphe = '';
    if ($info_cellule->{dh_assoc}) {
      $assoc_glyphe = "<p>Dernier calcul d'association $info_cellule->{dh_assoc} (UTC)</p>";
    }

    my $dessins = '';
    for my $gly (@{$info_cellule->{glyphes}}) {
      my $info_glyphe = get_glyphe($appli, $mdp, $gly->{car}, $gly->{num});
      my $img = img_cel_gly($appli, $mdp, $info_doc, $info_cellule, $info_glyphe);
      $dessins .= "<p><img src='data:image/png;base64," . encode_base64($img->png) . "' alt='comparaison cellule glyphe'/></p>\n";
    }
    my $caract_assoc = join ', ', map { sprintf "%s U+%X", $_, ord($_) } keys %{$info_cellule->{cpt_car}};
    $html = <<"EOF";
<h1>Cellule</h1>
<p>Ligne $l, colonne $c -&gt; x = $info_cellule->{xc}, y = $info_cellule->{yc}</p>
<p>Pixels noirs : $info_cellule->{nb_noir}, enveloppe $info_cellule->{lge} x $info_cellule->{hte} en ($info_cellule->{xe}, $info_cellule->{ye})</p>
<p>Score : $info_cellule->{score}, nombre de caractères associés $info_cellule->{nb_car} ($caract_assoc)</p>
<p>Créée le $info_cellule->{dh_cre} (UTC)</p>
$assoc_glyphe
$cre_glyphe
<h3>Association aux glyphes</h3>
<form action='/assocglyphe/$doc/$l/$c' method='post'>
<input type='submit' value='Association' />
</form>
<img src='data:image/png;base64,$voisinage' alt='cellule $doc en ligne $l et en colonne $c' />
<hr />
$dessins
EOF
  }
  else {
    $html = <<"EOF";
<p>Pas de cellule dans le document $doc en ligne $l et en colonne $c</p>
EOF
  }

  return <<"EOF";
<html>
<head>
<title>Cellule $doc $l $c</title>
</head>
<body>
Appli&nbsp;: $appli
<br /><a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>
<br /><a href='/doc/$doc'>Document $doc</a> (<a href='/grille/$doc'>grille</a>)
$html
</body>
</html>
EOF
};

sub aff_coloriage {
  my ($appli, $mdp, $doc, $n) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);

  my $info_coloriage;
  my ($action, $libelle);
  if ($n eq 'nouveau') {
    my @criteres = ( { } ) x 6;
    $info_coloriage = { criteres => [ @criteres ] };
    $action  = 'majcolor';
    $libelle = 'Création';
  }
  else {
    $info_coloriage = get_coloriage($appli, $mdp, $doc, $n);
    $action  = 'majcolor';
    $libelle = 'Mise à jour';
  }
  #say YAML::Dump($info_coloriage);
  my $html;
  my $dessins = '';
  my $html_crit= '';
  my @coul = palette();
  for my $i (0..5) {
    my $critere = $info_coloriage->{criteres}[$i];
    $critere->{select} //= '';
    my $sel_mult  = $critere->{select} eq 'multiple' ? "checked='1'" : "";
    my $sel_score = $critere->{select} eq 'score'    ? "checked='1'" : "";
    my $sel_carac = $critere->{select} eq 'carac'    ? "checked='1'" : "";
    my $score     = $critere->{seuil}  // 0;
    my $carac     = $critere->{caract} // '';
    my $espace    = $critere->{selspace} ? "checked='1'" : "";
    my $couleur   = $coul[$i];
    my $rouge     = $couleur->[0] // 255;
    my $vert      = $couleur->[1] // 255;
    my $bleu      = $couleur->[2] // 255;
    $html_crit .= <<"EOF";
<li style='background-color: rgb($rouge, $vert, $bleu)'>
    <input type='radio' name='select$i' value='multiple' $sel_mult  >cellule reliée à plusieurs caractères
 OU <input type='radio' name='select$i' value='score'    $sel_score >score ≥ <input type='text' name='seuil$i' value='$score'>
 OU <input type='radio' name='select$i' value='carac'    $sel_carac >associé à l'un des caractères <input type='text' name='caract$i' value='$carac'>
                        <input type='checkbox' name='selspace$i' $espace'>plus l'espace</li>
EOF
  }
  $html = <<"EOF";
<h1>Coloriage</h1>
<h3>Critères</h3>
<form action='/$action/$doc/$n' method='post'>
<ol>
$html_crit
</ol>
<input type='submit' value='$libelle' />
</form>
<h3>Résultat</h3>
<hr />
$dessins
EOF

  return <<"EOF";
<html>
<head>
<title>Coloriage</title>
</head>
<body>
Appli&nbsp;: $appli
<br /><a href='/'>Retour</a>
<br /><a href='/listedoc'>Liste</a>
<br /><a href='/doc/$doc'>Document $doc</a> (<a href='/grille/$doc'>grille</a>)
$html
</body>
</html>
EOF
};

sub score_cel {
  my ($appli, $mdp, $doc, $info_cellule) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);

  my $score_min  = 99999;
  my @glyphes    = ();
  my %car_cpt    = ();

  #say YAML::Dump($info_cellule);
  my $iter   = iter_glyphe($appli, $mdp);
  while (my $info_glyphe = $iter->next) {
    my $sc1 = comp_images($info_cellule, $info_glyphe);
    if ($sc1 < $score_min) {
      @glyphes = ( { car => $info_glyphe->{car}, num => $info_glyphe->{num} } );
      %car_cpt = ( $info_glyphe->{car1} => 1 );
      $score_min = $sc1;
    }
    elsif ($sc1 == $score_min) {
      push @glyphes, { car => $info_glyphe->{car}, num => $info_glyphe->{num} };
      $car_cpt{ $info_glyphe->{car1} } ++;
    }
  }
  return ($score_min, [ @glyphes ], { %car_cpt });
}
sub comp_images {
  my ($cel, $gly) = @_;
  my $im_cel = GD::Image->newFromPngData(decode_base64($cel->{data}));
  my $im_gly = GD::Image->newFromPngData(decode_base64($gly->{data}));
  my $lgc = $cel->{lge};
  my $htc = $cel->{hte};
  my $lgg = $gly->{lge};
  my $htg = $gly->{hte};
  my $lg = $lgc > $lgg ? $lgc : $lgg;
  my $ht = $htc > $htg ? $htc : $htg;
  my $score = 0;
  for my $y (0..$ht - 1) {
    for my $x (0..$lg - 1) {
      my ($pix_c, $pix_g); # 0 si blanc, 1 si noir
      if ($x <= $lgc && $y <= $htc) {
        $pix_c = ($cel->{ind_noir} == $im_cel->getPixel($x, $y));
      }
      else {
        $pix_c = 0;
      }
      if ($x <= $lgg && $y <= $htg) {
        $pix_g = ($gly->{ind_noir} == $im_gly->getPixel($x, $y));
      }
      else {
        $pix_g = 0;
      }
      if ($pix_c != $pix_g) {
        $score ++;
      }
    }
  }
  return $score;
}

sub img_cel_gly {
  my ($appli, $mdp, $info_doc, $info_cellule, $info_glyphe)= @_;
  my $echelle =  5;
  my $ecart   = 10;
  my $dx      = int($info_doc->{dx});
  my $dy      = int($info_doc->{dy});
  my $largeur = 3 * $echelle * $dx + 2 * $ecart;
  my $hauteur =     $echelle * $dy;
  my $image   = GD::Image->new($largeur, $hauteur);
  my $blanc   = $image->colorAllocate(255, 255, 255);
  my $noir    = $image->colorAllocate(  0,   0,   0);
  my $vert    = $image->colorAllocate(  0, 255,   0);
  my $bleu    = $image->colorAllocate(  0,   0, 255);
  my $orange  = $image->colorAllocate(255, 127,   0); # orange : pixels noir -> blancs
  my $cyan    = $image->colorAllocate(  0, 255, 255);
  my $xe      = $info_cellule->{xe};
  my $ye      = $info_cellule->{ye};
  my $lge     = $info_cellule->{lge};
  my $hte     = $info_cellule->{hte};
  my $im_cel = GD::Image->newFromPngData(decode_base64($info_cellule->{data}));
  my $im_gly = GD::Image->newFromPngData(decode_base64($info_glyphe->{data}));

  my $deltax = 0;
  $image->rectangle(0, 0, $echelle * $dx - 1, $echelle * $dy - 1, $bleu);
  $image->rectangle($echelle * $xe, $echelle * $ye,  $echelle * ($xe + $lge) - 1, $echelle * ($ye + $hte) - 1, $vert);
  for my $y (0 .. $hte - 1) {
    for my $x (0 .. $lge - 1) {
      if ($info_cellule->{ind_noir} == $im_cel->getPixel($x, $y)) {
        $image->filledRectangle($deltax + $echelle * ($xe + $x), $echelle * ($ye + $y), $deltax + $echelle * ($xe + $x + 1) - 2, $echelle * ($ye + $y + 1) - 2, $noir);
      }
    }
  }

  my $lgg     = $info_glyphe->{lge};
  my $htg     = $info_glyphe->{hte};
  $deltax     = 2 * ($ecart + $echelle * $dx);
  $image->rectangle($deltax + $echelle * $xe, $echelle * $ye, $deltax + $echelle * ($xe + $lgg) - 1, $echelle * ($ye + $htg) - 1, $vert);
  for my $y (0 .. $htg - 1) {
    for my $x (0 .. $lgg - 1) {
      if ($info_glyphe->{ind_noir} == $im_gly->getPixel($x, $y)) {
        $image->filledRectangle($deltax + $echelle * ($xe + $x), $echelle * ($ye + $y), $deltax + $echelle * ($xe + $x + 1) - 2, $echelle * ($ye + $y + 1) - 2, $noir);
      }
    }
  }

  my $lg = $lge > $lgg ? $lge : $lgg;
  my $ht = $hte > $htg ? $hte : $htg;
  $deltax  =  ($ecart + $echelle * $dx);
  for my $y (0 .. $ht - 1) {
    for my $x (0 .. $lg - 1) {
      my ($pix_c, $pix_g); # 0 si blanc, 1 si noir
      if ($x < $lge && $y < $hte) {
        $pix_c = 0 + ($info_cellule->{ind_noir} == $im_cel->getPixel($x, $y));
      }
      else {
        $pix_c = 0;
      }
      if ($x < $lgg && $y < $htg) {
        $pix_g = 0 + ($info_glyphe->{ind_noir} == $im_gly->getPixel($x, $y));
      }
      else {
        $pix_g = 0;
      }
        
      #if ($y == 21) { say "x = $x, pix_c = $pix_c, pix_g = $pix_g" }
      if ($pix_c != 0 || $pix_g != 0) {
        my @couleur = (0, $cyan, $orange, $noir);
        $image->filledRectangle($deltax + $echelle * ($xe + $x), $echelle * ($ye + $y), $deltax + $echelle * ($xe + $x + 1) - 2, $echelle * ($ye + $y + 1) - 2, $couleur[ 2 * $pix_c + $pix_g ]);
      }
    }
  }
             
  return $image;
}

sub palette {
  my ($variante) = @_;
  my @coul = ( [255, 192, 192],
               [192, 255, 192],   
               [192, 192, 255],   
               [255, 255, 192],   
               [192, 255, 255],   
               [255, 192, 255],   
      );
  #if ($variante eq 'html') {
  #  for (@coul) {
  #  }
  #}
  return @coul;
}

sub horodatage {
  return DateTime->now->strftime("%Y-%m-%d %H:%M:%S");
}

__END__

=encoding utf8

=head1 NOM

appli.pl - application interactive pour isoler et reconnaître les caractères dans une série de documents

=head1 DESCRIPTION

Ce programme tourne sous C<Dancer2> et permet de traiter les différents documents
contenant des textes à extraire.

=head1 LANCEMENT

Se placer dans le répertoire contenant les fichiers graphiques. S<Puis :>

  perl ../appli/appli.pl

(ou similaire, si le chemin pour trouver F<appli.pl> est différent de l'exemple ci-dessus).

=head1 COPYRIGHT et LICENCE

Copyright 2017, Jean Forget

Ce programme est diffusé avec les mêmes conditions que Perl 5.16.3 :
la licence publique GPL version 1 ou ultérieure, ou bien la
licence artistique Perl.

Vous pouvez trouver le texte en anglais de ces licences dans le
fichier <LICENSE> joint ou bien aux adresses
L<http://www.perlfoundation.org/artistic_license_1_0>
et L<http://www.gnu.org/licenses/gpl-1.0.html>.

Résumé en anglais de la GPL :

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 1, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., L<http://www.fsf.org/>.

