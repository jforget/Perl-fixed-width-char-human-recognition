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
use List::Util qw/min max/;
use experimental qw/switch/;

my %conv_car_car1 = ( ' ' => 'SP', '$' => 'DL', '.' => => 'PT', q(') => 'AP' );
my %conv_car1_car = reverse %conv_car_car1;

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

  redirect "/doc/$doc";
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
  #say "/grille/:doc -> get doc $doc (appli $appli, mdp $mdp)";
  return aff_doc($appli, $mdp, $doc, 'grille');
};

post '/majgrille/:doc' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  my %param;
  unless ($appli) {
    redirect '/';
  }
  for my $par (qw/dx dy num_gr/) {
    $param{$par} = body_parameters->get($par);
  }

  my @grille = ();
  for my $i (0..$param{num_gr}) {
    my $grille = {};
    for my $par (qw/l c action prio x0 y0 dx dy cish cisv dirh dirv/) {
      $grille->{$par} = body_parameters->get("$par$i") // '';
    }
    for my $par (qw/l c prio x0 y0 dx dy cish cisv/) {
      $grille->{$par} = 0 + ($grille->{$par} || 0);
    }
    push @grille, $grille;
  }
  #say YAML::Dump([ @grille ]);
  $param{grille} = [ @grille ];

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
  return aff_cellule($appli, $mdp, $doc, $l, $c, 1);
};

get '/top10/:doc/:l/:c' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }
  my $doc   = route_parameters->get('doc');
  my $l     = route_parameters->get('l');
  my $c     = route_parameters->get('c');
  #say "get doc $doc (appli $appli, mdp $mdp)";
  return aff_cellule($appli, $mdp, $doc, $l, $c, 10);
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
  # Élimination des caractères dangereux
  $param{desc} = body_parameters->get('desc');
  $param{desc} =~ s/(\W)/'&#' . ord($1) . ';'/eg;

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

post '/valcolor/:doc/:n' => sub {
  my $appli = setting('username');
  my $mdp   = setting('password');
  unless ($appli) {
    redirect '/';
  }

  my $doc = route_parameters->get('doc');
  my $n   = route_parameters->get('n');
  my $msg = valid_color($appli, $mdp, $doc, $n);
  redirect "/coloriage/$doc/$n";
};

start;

sub collection {
  my ($appli, $mdp, $coll) = @_;
  state $anc_appli = '';
  state $anc_mdp   = '';
  state $client;
  if ($appli ne $anc_appli or $mdp ne $anc_mdp) {
    $client = MongoDB->connect('mongodb://localhost', { db_name => $appli, username => $appli, password => $mdp } );
    $anc_appli = $appli;
    $anc_mdp   = $mdp;
  }
  return $client->ns("$appli.$coll");
}
sub liste_doc {
  my ($appli, $mdp) = @_;
  my $coll   = collection($appli, $mdp, "Document");
  my $doc    = $coll->find;
  #say YAML::Dump($doc);
  my @liste = $doc->all;
  return [ @liste ];
}

sub get_doc {
  my ($appli, $mdp, $doc) = @_;
  my $coll   = collection($appli, $mdp, "Document");
  my $obj    = $coll->find_one({ doc => $doc });
  # say YAML::Dump($obj);
  return $obj;
}

sub ins_doc {
  my ($appli, $mdp, $doc) = @_;
  my $coll   = collection($appli, $mdp, "Document");
  my $res    = $coll->insert_one($doc);
}

sub maj_doc {
  my ($appli, $mdp, $doc, $val) = @_;
  my $coll   = collection($appli, $mdp, "Document");
  my $result = $coll->update({ doc => $doc }, { '$set' => $val });
  return $result;
}

sub get_cellule {
  my ($appli, $mdp, $doc, $l, $c) = @_;
  my $coll   = collection($appli, $mdp, "Cellule");
  my $obj    = $coll->find_one({ doc => $doc, l => 0 + $l, c => 0 + $c });
  #my $obj    = $coll->find_one({ doc => $doc});
  #say "recherche $doc $l $c";
  #say YAML::Dump($obj);
  return $obj;
}

sub iter_cellule {
  my ($appli, $mdp, $critere) = @_;
  my $coll   = collection($appli, $mdp, "Cellule");
  my $iter   = $coll->find($critere);
  return $iter
}

sub ins_many_cellule {
  my ($appli, $mdp, $tab_cell) = @_;
  my $coll   = collection($appli, $mdp, "Cellule");
  my $result = $coll->insert_many($tab_cell);
  return $result;
}

sub maj_cellule {
  my ($appli, $mdp, $doc, $l, $c, $val) = @_;
  my $coll   = collection($appli, $mdp, "Cellule");
  my $result = $coll->update({ doc => $doc, l => 0 + $l, c => 0 + $c }, { '$set' => $val });
  return $result;
}

sub purge_cellule {
  my ($appli, $mdp, $doc) = @_;
  my $coll   = collection($appli, $mdp, "Cellule");
  my $result = $coll->remove({ doc => $doc });
  return $result;
}

sub stat_cellule {
  my ($appli, $mdp, $doc) = @_;
  my $coll   = collection($appli, $mdp, "Cellule");
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
  my $coll   = collection($appli, $mdp, "Glyphe");
  my $iter   = $coll->find({  });
  return $iter
}

sub get_glyphe {
  my ($appli, $mdp, $car, $num) = @_;
  my $coll   = collection($appli, $mdp, "Glyphe");
  my $obj    = $coll->find_one({ car => $car, num => 0 + $num });
  #say YAML::Dump($obj);
  return $obj;
}

sub get_glyphe_1 {
  my ($appli, $mdp, $car1, $num) = @_;
  my $coll   = collection($appli, $mdp, "Glyphe");
  my $obj    = $coll->find_one({ car1 => $car1, num => 0 + $num });
  #say YAML::Dump($obj);
  return $obj;
}

sub ins_glyphe {
  my ($appli, $mdp, $obj) = @_;
  my $coll   = collection($appli, $mdp, "Glyphe");
  $coll->insert_one($obj);
  #say YAML::Dump($obj);
  return $obj;
}

sub glyphe_max_1 {
  my ($appli, $mdp, $car1) = @_;
  my $coll   = collection($appli, $mdp, "Glyphe");
  my $result = $coll->aggregate( [ { '$match' => { 'car1' => $car1 }},
                                   { '$group' => { '_id' => '$car1', 'hnum' => { '$max' => '$num' }}} ] );
  my $num= $result->{_docs}[0]{hnum} // 0;
  #say YAML::Dump($result);
  return $num;
}

sub liste_coloriage {
  my ($appli, $mdp, $doc) = @_;
  my $coll   = collection($appli, $mdp, "Coloriage");
  my $iter   = $coll->find({ doc => $doc });
  my @liste  = $iter->all();
  return [ @liste ];
}

sub iter_coloriage {
  my ($appli, $mdp, $doc) = @_;
  my $coll   = collection($appli, $mdp, "Coloriage");
  my $iter   = $coll->find({ doc => $doc });
  return $iter;
}

sub get_coloriage {
  my ($appli, $mdp, $doc, $n) = @_;
  my $coll   = collection($appli, $mdp, "Coloriage");
  my $obj    = $coll->find_one({ doc => $doc, n => 0 + $n });
  #my $obj    = $coll->find_one({ doc => $doc});
  #say "recherche $doc $l $c";
  #say YAML::Dump($obj);
  return $obj;
}

sub ins_coloriage {
  my ($appli, $mdp, $doc, $n, $val) = @_;
  my $coll   = collection($appli, $mdp, "Coloriage");
  $val->{doc} = $doc;
  $val->{n}   = 0 + $n;
  my $res    = $coll->insert_one($val);
}

sub maj_coloriage {
  my ($appli, $mdp, $doc, $n, $val) = @_;
  my $coll   = collection($appli, $mdp, "Coloriage");
  my $result = $coll->update({ doc => $doc, n => 0 + $n }, { '$set' => $val });
  return $result;
}

sub verif_glyphe_espace {
  my ($appli, $mdp) = @_;
  my $obj = get_glyphe_1($appli, $mdp, 'SP', 1);
  unless ($obj) {
    my $image = GD::Image->new(3,3);
    my $blanc = $image->colorAllocate(255, 255, 255);
    ins_glyphe($appli, $mdp, { car       => ' ',
                               car1      => 'SP',
                               num       =>  1,
                               dh_cre    => horodatage(),
                               lge       =>  3,
                               hte       =>  3,
                               nb_noir   =>  0,
                               ind_noir  => -1, # -1 parce qu'il n'y a pas de noir et que colorExact renvoie -1
                               ind_blanc =>  0,
                               xg        =>  1,
                               yg        =>  1,
                               data      => encode_base64($image->png) } );
  }
  return $obj;
}

sub copie_cel_gly {
  my ($appli, $mdp, $doc, $l, $c, $car1) = @_;
  my $info_doc = get_doc($appli, $mdp, $doc);

  my $car;
  if (length($car1) == 2) {
    $car = $conv_car1_car{$car1};
  }
  else {
    $car  = $car1;
    $car1 = $conv_car_car1{$car} // $car;
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
                             xg        => $info_cellule->{xg},
                             yg        => $info_cellule->{yg},
                             data      => $info_cellule->{data},
                             dh_cre    => horodatage(),
                           } );
  my $result = maj_cellule($appli, $mdp, $doc, $l, $c, { score    => 0,
                                                         nb_car   => 1,
                                                         glyphes  => [ { car    => $car,
                                                                         num    => $num,
                                                                         xg_Cel => $info_cellule->{xg},
                                                                         yg_Cel => $info_cellule->{yg},
                                                                         xg_Gly => $info_cellule->{xg},
                                                                         yg_Gly => $info_cellule->{yg},
                                                                     } ],
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
  my %obj = ( doc => $doc, fic => $fic, dx => 30, dy => 50, etat => 1 );

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
  # heuristique : pour un Document, les pixels noirs sont beaucoup moins nombreux que les blancs
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
  $obj{dh_cre}   = horodatage();
  $obj{grille}   = [ { l    => 0,
                       c    => 0,
                       prio => 0,
                       x0   => $xmin[$obj{ind_noir}],
                       y0   => $ymin[$obj{ind_noir}],
                       dx   => $obj{dx},
                       dy   => $obj{dy},
                       cish => 0,
                       dirh => '',
                       cisv => 0,
                       dirv => '',
                     } ];

  ins_doc($appli, $mdp, { %obj });
  return '';
}

sub maj_grille {
  my ($appli, $mdp, $ref_param) = @_;
  my $doc      = $ref_param->{doc};

  my $info_doc = get_doc($appli, $mdp, $doc);
  #say YAML::Dump( $info_doc );

  my $fichier = "$doc-grille.png";
  $ref_param->{fic_grille} = $fichier;

  purge_cellule    ($appli, $mdp, $doc);
  my $iter_coloriage = iter_coloriage($appli, $mdp, $doc);
  while (my $info_col = $iter_coloriage->next) {
    my $n = $info_col->{n};
    maj_coloriage($appli, $mdp, $doc, $n, { cellules => [ ],
                                            dh_val   => horodatage(),
                                          } );
  }

  $ref_param->{grille} = maj_liste_grilles($info_doc, $ref_param);
  construire_grille($appli, $mdp, $info_doc, $ref_param, 0);

  $ref_param->{dh_grille}  = horodatage();
  $ref_param->{fic_grille} = $fichier;
  $ref_param->{etat}       = 2;
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

sub maj_liste_grilles {
  my ($info_doc, $ref_param) = @_;
  my @grille = @{$ref_param->{grille}};

  # pas de création si la dernière ligne n'a pas d'action
  if ($grille[-1]{action} eq 'rien') {
    pop @grille;
  }
  # Les autres suppressions
  @grille = sort { $a->{prio} cmp $b->{prio} } grep { $_->{action} ne 'suppr'} @grille;

  # Renuméroter les priorités
  my $prio = 0;
  for (@grille) {
    $_->{prio} = $prio ++;
  }

  for my $grille (@grille) {
    if ($grille->{action} eq 'rien') {
      # Implémentation de l'opération "rien" : on récupère les valeurs de la base de données
      # pour écraser celles saisies sur le formulaire
      # Cette boucle repose sur le fait que $grille est un alias des éléments de @grille
      for my $ancienne (@{$info_doc->{grille}}) {
        if ($grille->{l} == $ancienne->{l} && $grille->{c} == $ancienne->{c}) {
          for my $par (qw/x0 y0 dx dy cish cisv dirh dirv/) {
            $grille->{$par} = $ancienne->{$par};
          }
          last; # plus besoin de chercher
        }
      }
    }
    if ($grille->{action} eq 'calcul') {
      # Implémentation de l'opération "calcul" : on cherche une Grille de priorité inférieure
      # contenant la Grille en cours de calcul. Les paramètres x0 et y0 sont calculés d'après
      # les paramètres de cette Grille de référence et les autres sont recopiés.
      my @grille_ref = grep { $_->{prio} < $grille->{prio} && $_->{l} <= $grille->{l} && $_->{c} <= $grille->{c} } @grille;
      my $grille_ref = pop @grille_ref;
      for my $par (qw/dx dy cish cisv dirh dirv/) {
        $grille->{$par} = $grille_ref->{$par};
      }
      my ($x, $y) = calcul_xy($grille_ref, $grille->{l}, $grille->{c});
      $grille->{x0} = $x;
      $grille->{y0} = $y;
    }
  }
  return [ @grille ];
}

sub construire_grille {
  my ($appli, $mdp, $info_doc, $ref_param, $flag) = @_;

  my @cellule;

  my $image = GD::Image->newFromPng($info_doc->{fic});
  my $rouge = $image->colorAllocate(255,   0,   0);
  my $vert  = $image->colorAllocate(  0, 255,   0);
  my $bleu  = $image->colorAllocate(  0,   0, 255);

  my $noir    = $info_doc->{ind_noir};
  my $dx      = $ref_param->{dx};
  my $dy      = $ref_param->{dy};
  my @grille = @{$ref_param->{grille}};

  my $l_max = int($info_doc->{taille_y} / $dy);
  my $c_max = int($info_doc->{taille_x} / $dx);
  for my $l (0..$l_max) {
    for my $c (0..$c_max) {
      my @grille_ref = grep {  $_->{l} <= $l && $_->{c} <= $c } @grille;
      my $grille_ref = pop @grille_ref;
      my ($x, $y) = calcul_xy($grille_ref, $l, $c);
      my $dx = $grille_ref->{dx};
      my $dy = $grille_ref->{dy};
      my $couleur;

      # Dessin de la cellule dans la grille
      if ($flag == 0) {
        if ($c == $grille_ref->{c}) {
          $couleur = $bleu;
        }
        else {
          $couleur = $vert;
        }
        for my $y1 (0 .. $dy) {
          my $pixel = $image->getPixel($x, $y + $y1);
          if ($pixel == $noir || $pixel == $rouge) {
            $image->setPixel($x, $y + $y1, $rouge);
          }
          else {
            $image->setPixel($x, $y + $y1, $couleur);
          }
        }
        for my $y1 (0 .. $dy) {
          my $pixel = $image->getPixel($x +$dx, $y + $y1);
          if ($pixel == $noir || $pixel == $rouge) {
            $image->setPixel($x + $dx, $y + $y1, $rouge);
          }
          else {
            $image->setPixel($x + $dx, $y + $y1, $vert);
          }
        }
        if ($l == $grille_ref->{l}) {
          $couleur = $bleu;
        }
        else {
          $couleur = $vert;
        }
        for my $x1 (0 .. $dx) {
          my $pixel = $image->getPixel($x +$x1, $y);
          if ($pixel == $noir || $pixel == $rouge) {
            $image->setPixel($x + $x1, $y, $rouge);
          }
          else {
            $image->setPixel($x + $x1, $y, $couleur);
          }
        }
        for my $x1 (0 .. $dx) {
          my $pixel = $image->getPixel($x +$x1, $y + $dy);
          if ($pixel == $noir || $pixel == $rouge) {
            $image->setPixel($x + $x1, $y + $dy, $rouge);
          }
          else {
            $image->setPixel($x + $x1, $y + $dy, $vert);
          }
        }
      }

      # Extraction de la cellule
      if ($flag == 1) {
        # Compter les pixels noirs et repérer le plus haut, le plus bas,
        # le plus à gauche et le plus à droite
        my $nb_noir = 0;  
        my ($xmin, $xmax, $ymin, $ymax) = ($dx, 0, $dy, 0);
        my ($xx, $yy) = (0,0);
        for my $x1 (0 .. $dx - 1) {
          for my $y1 (0 .. $dy - 1) {
            my $pixel = $image->getPixel($x +$x1, $y + $y1);
            if ($pixel == $noir) {
              $nb_noir++;
              $xmin = $x1 if $xmin > $x1;
              $xmax = $x1 if $xmax < $x1;
              $ymin = $y1 if $ymin > $y1;
              $ymax = $y1 if $ymax < $y1;
              $xx  += $x1;
              $yy  += $y1;
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
          my $ind_blanc = $cellule->colorExact(255, 255, 255),
          my $ind_noir = $cellule->colorExact(  0,   0,   0),

          # Le voisinage : la cellule et les 24 cellules environnantes
          my $x_dep = $x - 2 * $dx;
          my $y_dep = $y - 2 * $dy;
          my $x_arr = 0;
          my $y_arr = 0;
          if ($x_dep < 0) {
            $x_arr = - $x_dep;
            $x_dep = 0;
          }
          elsif ($x_dep > $info_doc->{taille_x}) {
            $x_dep = $info_doc->{taille_x};
          }
          if ($y_dep < 0) {
            $y_arr = - $y_dep;
            $y_dep = 0;
          }
          elsif ($y_dep > $info_doc->{taille_y}) {
            $y_dep = $info_doc->{taille_y};
          }
          my $voisinage = GD::Image->new(5 * $dx, 5 * $dy); 
          $voisinage->copy($image, $x_arr, $y_arr, $x_dep, $y_dep, 5 * $dx, 5 * $dy); 

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
                               # centre de gravité (relatif au coin en haut à gauche de l'enveloppe)
                               xg        => $xx / $nb_noir - $xmin,
                               yg        => $yy / $nb_noir - $ymin,
                               # graphisme
                               ind_blanc => $ind_blanc,
                               ind_noir  => $ind_noir,
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
    my $fichier = $ref_param->{fic_grille};
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

sub valid_color  {
  my($appli, $mdp, $doc, $n) = @_;
  my $info_doc = get_doc      ($appli, $mdp, $doc);
  my $info_col = get_coloriage($appli, $mdp, $doc, $n);
  my $iter     = iter_cellule ($appli, $mdp, { doc => $doc });
  my @criteres = @{$info_col->{criteres}};

  my $image = GD::Image->newFromPng($info_doc->{fic});
  my $noir    = $info_doc->{ind_noir};
  my @coul;
  for (palette()) {
    my $coul = $image->colorAllocate(@$_);
    push @coul, $coul;
  }

  my @cellules = ();
  while (my $info_cellule = $iter->next) {
    my $cell = {}; # Informations abrégées de la Cellule, recopiées dans le Coloriage
    for (qw/l c xc yc lge hte/) {
      $cell->{$_} = $info_cellule->{$_};
    }
  CRIT:
    for (my $i = 0; $i < @criteres; ++$i) {
      my $critere = $criteres[$i];
      given ($critere->{select}) {
        when ('multiple') {
          if ($info_cellule->{nb_car} > 1) {
            $cell->{crit}   = $i;
            $cell->{select} = $critere->{select};
            push @cellules, $cell;
            last CRIT;
          }
        }
        when ('score') {
          if ($info_cellule->{score} >= $critere->{seuil}) {
            $cell->{crit}   = $i;
            $cell->{select} = $critere->{select};
            push @cellules, $cell;
            last CRIT;
          }
        }
        when ('carac') {
          my $ok = 0;
          my $car = $info_cellule->{glyphes}[0]{car};
          if ($critere->{selspace} ne '' && ($car eq 'SP' || $car eq ' ')) {
            $ok = 1;
          }
          if (index($critere->{caract}, $car) >= 0) {
            $ok = 1;
          }
          if ($ok) {
            $cell->{crit}   = $i;
            $cell->{select} = $critere->{select};
            push @cellules, $cell;
            last CRIT;
          }
        }
      }
    }
    if ($cell->{select})  {
      my $xc = $cell->{xc};
      my $yc = $cell->{yc};
      for (my $dx = 0; $dx < $info_doc->{dx}; $dx++) {
        for (my $dy = 0; $dy < $info_doc->{dy}; $dy++) {
          my $pixel = $image->getPixel($xc +$dx, $yc + $dy);
          if ($pixel != $noir) {
            $image->setPixel($xc + $dx, $yc + $dy, $coul[$cell->{crit}]);
          }
        }
      }
    }
  }
  #say YAML::Dump([ @cellules ]);

  # Fichier résultat
  my $nom_fic = "$doc-col$n.png";
  open my $im, '>', $nom_fic
    or die "Ouverture $nom_fic $!";
  print $im $image->png;
  close $im
    or die "Fermeture $nom_fic $!";

  # Base de données
  maj_coloriage($appli, $mdp, $doc, $n, { cellules => [ @cellules ],
                                          dh_val   => horodatage(),
                                          fic      => $nom_fic,
                                        } );
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
  for (sort { $a->{doc} cmp $b->{doc} } @{$liste_ref}) {
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
  # Table des Grilles
  my $table = '';
  my $num_gr = 0;
  for my $grille (@{$info->{grille}}) {
    my %case;
    my $l = sprintf "<td>%d <input name='l%d' type='hidden' value='%d' /></td>\n", $grille->{l}, $num_gr, $grille->{l};
    my $c = sprintf "<td>%d <input name='c%d' type='hidden' value='%d' /></td>\n", $grille->{c}, $num_gr, $grille->{c};
    my $action;
    my $prio;
    if ($grille->{l} == 0 && $grille->{c} == 0) {
      $action = "<td><select name='action0' size='1'><option>rien</option><option>saisie</option></select></td>\n";
      $prio = "<td>0<input name='prio0' type='hidden' value='0'></td>\n";
    }
    else {
      $action = "<td><select name='action$num_gr' size='1'><option>rien</option><option>saisie</option><option>calcul</option><option>suppr</option></select></td>\n";
      $prio = sprintf "<td><input name='prio%d' value='%d' size='6'></td>\n", $num_gr, $grille->{prio};
    }
    for my $param (qw/x0 y0 dx dy cish cisv/) {
      my $valeur = sprintf("%.2f", $grille->{$param});
      # suppression des zéros de droite de la partie décimale
      $valeur =~ s/0+$//;
      $valeur =~ s/\.$//;
      $case{$param} = sprintf "<td><input name='%s%d' value='%s' size='6' /></td>", $param, $num_gr, $valeur;
    }

    if ($grille->{dirh} eq 'gauche') {
      $case{dirh} = "<td><select name='dirh$num_gr'><option selected='1'>gauche</option><option>droite</option></select></td>";
    }
    elsif ($grille->{dirh} eq 'droite') {
      $case{dirh} = "<td><select name='dirh$num_gr'><option>gauche</option><option selected='1'>droite</option></select></td>";
    }
    else {
      $case{dirh} = "<td><select name='dirh$num_gr'><option>gauche</option><option>droite</option></select></td>";
    }

    if ($grille->{dirv} eq 'haut') {
      $case{dirv} = "<td><select name='dirv$num_gr'><option selected='1'>haut</option><option>bas</option></select></td>";
    }
    elsif ($grille->{dirv} eq 'bas') {
      $case{dirv} = "<td><select name='dirv$num_gr'><option>haut</option><option selected='1'>bas</option></select></td>";
    }
    else {
      $case{dirv} = "<td><select name='dirv$num_gr'><option>haut</option><option>bas</option></select></td>";
    }
    $table .= "<tr>$l$c$prio$action" . (join '', @case{ qw/x0 y0 dx dy dirh cish dirv cisv/ }) . "</tr>\n";
    $num_gr ++;
  }
  $table .= <<"EOF";
<tr><td><input name='l$num_gr' size='3' /></td><td><input name='c$num_gr' size='3' /></td>
    <td><input name='prio$num_gr' size='3' /></td>
    <td><select name='action$num_gr' size='1'><option selected='1'>rien</option><option>saisie</option><option>calcul</option></select></td>
    <td><input name='x0$num_gr' size='3' /></td>
    <td><input name='y0$num_gr' size='3' /></td>
    <td><input name='dx$num_gr' size='3' /></td>
    <td><input name='dy$num_gr' size='3' /></td>
    <td><select name='dirh$num_gr' size='1'><option>gauche</option><option>droite</option></select></td>
    <td><input name='cish$num_gr' size='3' /></td>
    <td><select name='dirv$num_gr' size='1'><option>haut</option><option>bas</option></select></td>
    <td><input name='cisv$num_gr' size='3' /></td>
EOF
  # Quel fichier graphique faut-il afficher ?
  my $fichier;
  given ($variante) {
    when ('base'  ) { $fichier = $info->{fic}       ; }
    when ('grille') { $fichier = $info->{fic_grille}; }
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
    $coloriage = join ' ', map { sprintf "<a href='/coloriage/$doc/%d'>%d %s</a><br />", $_->{n}, $_->{n}, $_->{desc} } @$liste;
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
Taille des cellules&nbsp;: largeur <input type='text' name='dx' value='$info->{dx}' /> hauteur <input type='text' name='dy' value='$info->{dy}' />
<input name='num_gr' value='$num_gr' type='hidden' />
<table border='1'>
<tr><th colspan='2'>En haut à gauche</th>
    <th></th><th></th>
    <th colspan='2'>Coordonnées pixel</th>
    <th colspan='2'>Décalage</th>
    <th colspan='2'>Cisaillement horizontal</th>
    <th colspan='2'>Cisaillement vertical</th></tr>
<tr><th>ligne</th><th>colonne</th>
    <th>priorité</th><th>Action</th>
    <th>x0</th><th>y0</th>
    <th>dx</th><th>dy</th>
    <th>1 pixel <br />vers la</th><th>toutes les <br /><var>n</var> lignes</th>
    <th>1 pixel <br />vers le</th><th>toutes les <br /><var>n</var> colonnes</th></tr>
$table
</table>
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
  my ($appli, $mdp, $doc, $l, $c, $nb) = @_;
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
    my @glyphes;
    if ($nb == 1) {
      @glyphes= @{$info_cellule->{glyphes}};
    }
    else {
      @glyphes= ();
      my %glyphes_par_score = ();
      my $iter = iter_glyphe($appli, $mdp);
      while (my $info_glyphe = $iter->next) {
        my @essai = comp_images($info_cellule, $info_glyphe);
        for my $essai (@essai) {
          my $sc1 = $essai->{score};
          push @{$glyphes_par_score{$sc1}}, $essai;
        }
      }
      my $lus = 0;
      for my $sc1 (sort { $a <=> $b } keys %glyphes_par_score) {
        push @glyphes,  @{$glyphes_par_score{$sc1}};
        $lus += 0 + @{$glyphes_par_score{$sc1}};
        last if $lus >= $nb;
      }
    }
    #say YAML::Dump(\@glyphes);
    for my $gly (@glyphes) {
      my $info_glyphe = get_glyphe($appli, $mdp, $gly->{car}, $gly->{num});
      my $score    = $gly->{score} // $info_cellule->{score};
      my $img      = img_cel_gly($appli, $mdp, $info_doc, $info_cellule, $info_glyphe, $gly);
      my $centre_C = sprintf("<p>Centre de gravité en %.2f, %.2f par rapport à l'enveloppe arrondi à %d, %d</p>",
                             $info_cellule->{xg}, $info_cellule->{yg}, $gly->{xg_Cel}, $gly->{yg_Cel});
      my $centre_G = sprintf("<p>Centre de gravité du Glyphe « %s » (U+00%2X) n° %d en %.2f, %.2f arrondi à %d, %d</p>",
                             $info_glyphe->{car1}, ord($gly->{car}), $gly->{num}, $info_glyphe->{xg}, $info_glyphe->{yg}, $gly->{xg_Gly}, $gly->{yg_Gly});
      my $png      = encode_base64($img->png);
      $dessins .= <<"EOF";
<h3>Score $score</h3>
$centre_C
$centre_G
<p><img src='data:image/png;base64,$png' alt='comparaison cellule glyphe'/></p>
EOF
    }
    my @caract_assoc;
    for (keys %{$info_cellule->{cpt_car}}) {
      if (length($_) == 2) {
        push @caract_assoc, sprintf("%s U+00%X", $_, ord($conv_car1_car{$_}));
      }
      else {
        push @caract_assoc, sprintf("&#%d; U+00%X", ord($_), ord($_));
      }
    }
    my $caract_assoc = join ', ', @caract_assoc;
    my $centre_g = sprintf("<p>Centre de gravité en %.2f, %.2f par rapport à l'enveloppe, en %.2f, %.2f par rapport à la cellule</p>",
                           $info_cellule->{xg}, $info_cellule->{yg},
                           $info_cellule->{xe} + $info_cellule->{xg}, $info_cellule->{ye} + $info_cellule->{yg});
    $html = <<"EOF";
<h1>Cellule</h1>
<p>Ligne $l, colonne $c -&gt; x = $info_cellule->{xc}, y = $info_cellule->{yc}</p>
<p>Pixels noirs : $info_cellule->{nb_noir}, enveloppe $info_cellule->{lge} x $info_cellule->{hte} en ($info_cellule->{xe}, $info_cellule->{ye})</p>
$centre_g
<p>Score : $info_cellule->{score}, nombre de caractères associés $info_cellule->{nb_car} ($caract_assoc), <a href='/top10/$doc/$l/$c'>top 10 des Glyphes</a></p>
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
  my $desc;
  my ($dates, $action, $libelle, $validation);
  if ($n eq 'nouveau') {
    my @criteres = ( { } ) x 6;
    $info_coloriage = { criteres => [ @criteres ] };
    $dates          = '';
    $action         = 'majcolor';
    $libelle        = 'Création';
    $validation     = '';
    $desc           = '';
  }
  else {
    $info_coloriage = get_coloriage($appli, $mdp, $doc, $n);
    $dates      = "Créé le $info_coloriage->{dh_cre} (UTC)";
    if ($info_coloriage->{dh_maj}){
      $dates .= "<br />Modifié le $info_coloriage->{dh_maj} (UTC)";
    }
    if ($info_coloriage->{dh_val}){
      $dates .= "<br />Validé le $info_coloriage->{dh_val} (UTC)";
    }
    $desc       = " value='$info_coloriage->{desc}'";
    $action     = 'majcolor';
    $libelle    = 'Mise à jour';
    $validation = <<"EOF";
<h3>Validation</h3>
<form action='/valcolor/$doc/$n' method='post'>
<input type='submit' value='Validation' />
</form>
EOF
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
    $carac =~ s/(\W)/sprintf("&#%d", ord($1))/ge;
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
                        <input type='checkbox' name='selspace$i' $espace>plus l'espace</li>
EOF
  }

  if ($info_coloriage->{fic}) {
    my $image = GD::Image->newFromPng($info_coloriage->{fic});
    $dessins  = encode_base64($image->png);
    my @map;
    my $largeur = int($info_doc->{dx});
    my $hauteur = int($info_doc->{dy});
    for my $cel (@{$info_coloriage->{cellules}}) {
      my %cel = %$cel;
      my ($xg, $yh, $l, $c) = @cel{ qw/xc yc l c/ };
      my $xd = $xg + $largeur;
      my $yb = $yh + $hauteur;
      push @map, "<area coords='$xg,$yh,$xd,$yb' href='/cellule/$doc/$l/$c' />";
    }
    my $map = join "\n", @map;
    $dessins  = <<"EOF";
<img src='data:image/png;base64,$dessins' alt='document $doc' usemap='#carte' />
<map name='carte'>
$map
</map>
EOF
  }

  $html = <<"EOF";
<h1>Coloriage</h1>
$dates
<h3>Critères</h3>
<form action='/$action/$doc/$n' method='post'>
<input type='text' name='desc' $desc />
<ol>
$html_crit
</ol>
<input type='submit' value='$libelle' />
</form>
$validation
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
    my @essai = comp_images($info_cellule, $info_glyphe);
    for my $essai (@essai) {
      my $sc1 = $essai->{score};
      if ($sc1 < $score_min) {
        @glyphes = ( { car    => $info_glyphe->{car},
                       num    => $info_glyphe->{num},
                       xg_Cel => $essai->{xg_Cel},
                       yg_Cel => $essai->{yg_Cel},
                       xg_Gly => $essai->{xg_Gly},
                       yg_Gly => $essai->{yg_Gly},
                      } );
        %car_cpt = ( $info_glyphe->{car1} => 1 );
        $score_min = $sc1;
      }
      elsif ($sc1 == $score_min) {
        push @glyphes, { car    => $info_glyphe->{car},
                         num    => $info_glyphe->{num},
                         xg_Cel => $essai->{xg_Cel},
                         yg_Cel => $essai->{yg_Cel},
                         xg_Gly => $essai->{xg_Gly},
                         yg_Gly => $essai->{yg_Gly},
                      };
        $car_cpt{ $info_glyphe->{car1} } ++;
      }
    }
  }
  return ($score_min, [ @glyphes ], { %car_cpt });
}
sub comp_images {
  my ($cel, $gly) = @_;
  my $im_cel = GD::Image->newFromPngData(decode_base64($cel->{data}));
  my $im_gly = GD::Image->newFromPngData(decode_base64($gly->{data}));

  # Essais à effectuer en faisant varier les arrondis
  my @essai;
  my %essai_de_base = (xg_Cel => int($cel->{xg}),
                       yg_Cel => int($cel->{yg}),
                       xg_Gly => int($gly->{xg}),
                       yg_Gly => int($gly->{yg}),
                       car    =>     $gly->{car},
                       num    =>     $gly->{num},
                      );
  for (0..8) {
    $essai[$_] = { %essai_de_base };
  }
  for (3, 4, 5) {
    $essai[$_]{xg_Cel}++;
  }
  for (6, 7, 8) {
    $essai[$_]{xg_Gly}++;
  }
  for (1, 4, 7) {
    $essai[$_]{yg_Cel}++;
  }
  for (2, 5, 8) {
    $essai[$_]{yg_Gly}++;
  }
  #say join ' ', ($cel->{xg}, $cel->{yg}, $gly->{xg}, $gly->{yg});
  #say YAML::Dump([ @essai ]);

  my $lgc = $cel->{lge};
  my $htc = $cel->{hte};
  my $lgg = $gly->{lge};
  my $htg = $gly->{hte};

  for my $num_essai (0..$#essai) {
    # Plages de valeurs combinées pour x et y, relativement au CDG
    my ($dep_x, $arr_x, $dep_y, $arr_y);
    $dep_x = max(         - $essai[$num_essai]{xg_Cel},          - $essai[$num_essai]{xg_Gly});
    $arr_x = min($lgc - 1 - $essai[$num_essai]{xg_Cel}, $lgg - 1 - $essai[$num_essai]{xg_Gly});
    $dep_y = max(         - $essai[$num_essai]{yg_Cel},          - $essai[$num_essai]{yg_Gly});
    $arr_y = min($htc - 1 - $essai[$num_essai]{yg_Cel}, $htg - 1 - $essai[$num_essai]{yg_Gly});

    # Plages de valeurs combinées, mais relativement au coin en haut à gauche des dessins respectifs
    my $dep_x_Cel = $dep_x + $essai[$num_essai]{xg_Cel};
    my $arr_x_Cel = $arr_x + $essai[$num_essai]{xg_Cel};
    my $dep_y_Cel = $dep_y + $essai[$num_essai]{yg_Cel};
    my $arr_y_Cel = $arr_y + $essai[$num_essai]{yg_Cel};
    my $dep_x_Gly = $dep_x + $essai[$num_essai]{xg_Gly};
    my $arr_x_Gly = $arr_x + $essai[$num_essai]{xg_Gly};
    my $dep_y_Gly = $dep_y + $essai[$num_essai]{yg_Gly};
    my $arr_y_Gly = $arr_y + $essai[$num_essai]{yg_Gly};
    #say "$dep_y_Cel $arr_y_Cel $dep_y_Gly $arr_y_Gly";

    my $commun = 0;
    my ($x_Cel, $y_Cel, $x_Gly, $y_Gly);

    for ($y_Cel  = $dep_y_Cel, $y_Gly = $dep_y_Gly;
         $y_Cel <= $arr_y_Cel;
         $y_Cel++, $y_Gly++) {

        for ($x_Cel  = $dep_x_Cel, $x_Gly = $dep_x_Gly;
             $x_Cel <= $arr_x_Cel;
             $x_Cel ++, $x_Gly++) {

        my ($pix_Cel, $pix_Gly); # 0 si blanc, 1 si noir
        $pix_Cel = ($cel->{ind_noir} == $im_cel->getPixel($x_Cel, $y_Cel));
        $pix_Gly = ($gly->{ind_noir} == $im_gly->getPixel($x_Gly, $y_Gly));
        if ($pix_Cel == 1 && $pix_Gly == 1) {
          $commun++;
        }

      }
    }
    $essai[$num_essai]{score} = $cel->{nb_noir} + $gly->{nb_noir} - 2 * $commun;
    #say "$essai[$num_essai]{score} = $cel->{nb_noir} + $gly->{nb_noir} - 2 * $commun";
  }
  #printf("Glyphe « %s » (U+00%2X) n° %d\n", $gly->{car1}, ord($gly->{car}), $gly->{num});
  #say YAML::Dump([ @essai ]);

  return @essai;
}

sub img_cel_gly {
  my ($appli, $mdp, $info_doc, $info_cellule, $info_glyphe, $info_rel)= @_;
  my $echelle =  5;
  my $ecart   = 10;
  my $dx      = int($info_doc->{dx});
  my $dy      = int($info_doc->{dy});
  my $largeur = 4 * $echelle * $dx + 2 * $ecart; # * 4 pour avoir de la marge si le Glyphe déborde de la Cellule
  my $hauteur =     $echelle * $dy;
  my $image   = GD::Image->new($largeur, $hauteur);
  my $blanc   = $image->colorAllocate(255, 255, 255);
  my $noir    = $image->colorAllocate(  0,   0,   0);
  my $vert    = $image->colorAllocate(  0, 255,   0);
  my $bleu    = $image->colorAllocate(  0,   0, 255);
  my $orange  = $image->colorAllocate(255, 127,   0); # orange : pixels noir -> blancs
  my $cyan    = $image->colorAllocate(  0, 255, 255);
  my $jaune   = $image->colorAllocate(255, 255, 192);
  my $xe      = $info_cellule->{xe};
  my $ye      = $info_cellule->{ye};
  my $lge     = $info_cellule->{lge};
  my $hte     = $info_cellule->{hte};
  my $xg      = $info_rel->{xg_Cel};
  my $yg      = $info_rel->{yg_Cel};
  my $im_cel = GD::Image->newFromPngData(decode_base64($info_cellule->{data}));
  my $im_gly = GD::Image->newFromPngData(decode_base64($info_glyphe->{data}));

  my $deltax = 0;
  # Grille des pixels pour la Cellule
  for (my $x = 0; $x < $echelle * $dx; $x += $echelle) {
    $image->line($x, 0, $x, $echelle * $dy - 1, $jaune);
  }
  for (my $y = 0; $y < $hauteur; $y += $echelle) {
    $image->line(0, $y, $echelle * $dx - 1, $y, $jaune);
  }

  # Périmètre de la Cellule et périmètre de l'enveloppe
  $image->rectangle(0, 0, $echelle * $dx - 1, $echelle * $dy - 1, $bleu);
  $image->rectangle($echelle * $xe, $echelle * $ye,  $echelle * ($xe + $lge) - 1, $echelle * ($ye + $hte) - 1, $vert);

  # centre de gravité de la Cellule
  my ($x1, $y1, $x2, $y2);
  $x1 = 0;
  $y1 = $echelle * ($ye + $yg + 0.5);
  $y2 = $y1;
  $x2 = $echelle * $dx - 1;
  $image->line     ($x1, $y1, $x2, $y2, $vert);
  $x1 = $echelle * ($xe + $xg + 0.5);
  $y1 = 0;
  $x2 = $x1;
  $y2 = $echelle * $dy - 1;
  $image->line     ($x1, $y1, $x2, $y2, $vert);

  for my $y (0 .. $hte - 1) {
    for my $x (0 .. $lge - 1) {
      if ($info_cellule->{ind_noir} == $im_cel->getPixel($x, $y)) {
        $image->filledRectangle($deltax + $echelle * ($xe + $x), $echelle * ($ye + $y), $deltax + $echelle * ($xe + $x + 1) - 2, $echelle * ($ye + $y + 1) - 2, $noir);
      }
    }
  }
  my $lgc     = $info_cellule->{lge};
  my $htc     = $info_cellule->{hte};

  my $lgg     = $info_glyphe->{lge};
  my $htg     = $info_glyphe->{hte};
  my $xgg     = $info_rel->{xg_Gly};
  my $ygg     = $info_rel->{yg_Gly};
  $deltax     = 2 * ($ecart + $echelle * $dx) + $echelle * ($xe + $xg - $xgg);
  my $deltay  = $echelle * ($ye + $yg - $ygg);
  $image->rectangle($deltax + $echelle * $xe,              $deltay,
                    $deltax + $echelle * ($xe + $lgg) - 1, $deltay + $echelle * $htg - 1, $vert);

  # centre de gravité du Glyphe
  my $fin_ligne = max($dx, $xe + $lgg);
  $image->line     ($deltax                          , $deltay + $echelle * ($ygg + 0.5),
                    $deltax + $echelle * $fin_ligne - 1    , $deltay + $echelle * ($ygg + 0.5), $vert);
  $image->line     ($deltax + $echelle * ($xe + $xgg + 0.5), 0,
                    $deltax + $echelle * ($xe + $xgg + 0.5), $echelle * $dy - 1     , $vert);

  for my $y (0 .. $htg - 1) {
    for my $x (0 .. $lgg - 1) {
      if ($info_glyphe->{ind_noir} == $im_gly->getPixel($x, $y)) {
        $image->filledRectangle($deltax + $echelle * ($xe + $x),         $deltay + $echelle *  $y,
                                $deltax + $echelle * ($xe + $x + 1) - 2, $deltay + $echelle * ($y + 1) - 2, $noir);
      }
    }
  }

  my $lg = $lge > $lgg ? $lge : $lgg;
  my $ht = $hte > $htg ? $hte : $htg;

  # Plages de valeurs combinées pour x et y, relativement au CDG
  my ($dep_x, $arr_x, $dep_y, $arr_y);
  $dep_x = min(         - $info_rel->{xg_Cel},          - $info_rel->{xg_Gly});
  $arr_x = max($lgc - 1 - $info_rel->{xg_Cel}, $lgg - 1 - $info_rel->{xg_Gly});
  $dep_y = min(         - $info_rel->{yg_Cel},          - $info_rel->{yg_Gly});
  $arr_y = max($htc - 1 - $info_rel->{yg_Cel}, $htg - 1 - $info_rel->{yg_Gly});

  # Plages de valeurs combinées, mais relativement au coin en haut à gauche des dessins respectifs
  my $dep_x_Cel = $dep_x + $info_rel->{xg_Cel};
  my $arr_x_Cel = $arr_x + $info_rel->{xg_Cel};
  my $dep_y_Cel = $dep_y + $info_rel->{yg_Cel};
  my $arr_y_Cel = $arr_y + $info_rel->{yg_Cel};
  my $dep_x_Gly = $dep_x + $info_rel->{xg_Gly};
  my $arr_x_Gly = $arr_x + $info_rel->{xg_Gly};
  my $dep_y_Gly = $dep_y + $info_rel->{yg_Gly};
  my $arr_y_Gly = $arr_y + $info_rel->{yg_Gly};

  $deltax  =  ($ecart + $echelle * $dx);
  my ($x_Cel, $y_Cel, $x_Gly, $y_Gly);

  for ($y_Cel  = $dep_y_Cel, $y_Gly = $dep_y_Gly;
       $y_Cel <= $arr_y_Cel;
       $y_Cel++, $y_Gly++) {

    for ($x_Cel  = $dep_x_Cel, $x_Gly = $dep_x_Gly;
         $x_Cel <= $arr_x_Cel;
         $x_Cel ++, $x_Gly++) {

      my ($pix_c, $pix_g); # 0 si blanc, 1 si noir
      if ($x_Cel>= 0 && $x_Cel < $lge && $y_Cel >= 0 && $y_Cel < $hte) {
        $pix_c = 0 + ($info_cellule->{ind_noir} == $im_cel->getPixel($x_Cel, $y_Cel));
      }
      else {
        $pix_c = 0;
      }
      if ($x_Gly >= 0 && $x_Gly < $lgg && $y_Gly >= 0 && $y_Gly < $htg) {
        $pix_g = 0 + ($info_glyphe->{ind_noir} == $im_gly->getPixel($x_Gly, $y_Gly));
      }
      else {
        $pix_g = 0;
      }
        
      #if ($y == 21) { say "x = $x, pix_c = $pix_c, pix_g = $pix_g" }
      if ($pix_c != 0 || $pix_g != 0) {
        my @couleur = (0, $cyan, $orange, $noir);
        $image->filledRectangle($deltax + $echelle * ($xe + $x_Cel),         $echelle * ($ye + $y_Cel),
                                $deltax + $echelle * ($xe + $x_Cel + 1) - 2, $echelle * ($ye + $y_Cel + 1) - 2,
                                $couleur[ 2 * $pix_c + $pix_g ]);
      }
    }
  }
             
  return $image;
}

sub calcul_xy {
  my ($ref_param, $l, $c) = @_;
  my $l0      = $ref_param->{l};
  my $c0      = $ref_param->{c};
  my $x0      = $ref_param->{x0};
  my $y0      = $ref_param->{y0};
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
  my $x = int($x0 + $coef_cx * ($c - $c0) + $coef_lx * ($l - $l0));
  my $y = int($y0 + $coef_cy * ($c - $c0) + $coef_ly * ($l - $l0));
  return ($x, $y);
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

sub frac {
  return $_[0] - int($_[0]);
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

