/*
 * ============================================================
 *  FLICK SOCCER LAN  -  Fútbol de fichas multijugador en red local
 *  Processing (Java)
 * ============================================================
 *  PESTAÑA PRINCIPAL: FlickSoccer.pde
 *  (la carpeta del sketch tiene que llamarse FlickSoccer)
 *
 *  Pestañas:
 *    FlickSoccer.pde : setup, draw, estados, reglas, mouse, teclado, mensajes de red, dibujo
 *    Ficha.pde       : clase Ficha (jugadores, arqueros y pelota): física y choques
 *    Redes.pde       : clase Red (hilo que lee la red, sirve de servidor o de cliente)
 *    Particula.pde   : clases Particula y SistemaParticulas (confeti)
 *
 *  Reglas:
 *    - Cada equipo tiene 1 arquero (aro dorado) y 5 jugadores.
 *    - Se juega por turnos. Clic en una ficha tuya, arrastrá hacia atrás
 *      (como una gomera) y soltá: la ficha sale en sentido contrario.
 *    - PASES: si cuando todo se frena la última ficha que tocó la pelota
 *      es un compañero del que tiró, fue un pase y el mismo equipo vuelve a
 *      tirar. Máximo 4 tiros seguidos por turno. Si no hubo pase, juega el rival.
 *    - Gana el primero que llega a 5 goles.
 *
 *  Modos (menú, con botones del mouse): Crear partida = servidor,
 *  Unirse = cliente, Modo local = los dos en esta compu.
 *
 *  Idea de la red: el SERVIDOR calcula toda la física y las reglas.
 *  El CLIENTE sólo manda su tiro (MOV) y dibuja lo que le llega (POS).
 *
 *  Las variables en MAYÚSCULAS se usan como constantes por convención,
 *  pero son variables comunes.
 * ============================================================
 */

import processing.net.*;

// ---------- Cancha (en píxeles) ----------
int campoX = 60;
int campoY = 90;
int campoAncho = 880;
int campoAlto = 520;
int golAlto = 180;          // tamaño de la boca del arco
int golProf = 40;           // profundidad del arco (la red)
float golY1;                // borde de arriba de la boca del arco
float golY2;                // borde de abajo de la boca del arco
float radioPoste = 7;

// ---------- Reglas y físicas ----------
int PUERTO = 5204;
int GOLES_PARA_GANAR = 5;
int MAX_TIROS = 4;          // tiros seguidos por turno (con pases)
float MAX_ARRASTRE = 120;   // cuánto se puede estirar la gomera
float FACTOR_TIRO = 0.12;   // de píxeles arrastrados a velocidad
float FACTOR_ARQUERO = 0.6; // el arquero sale con menos fuerza
float VEL_MAX = 18;
float REBOTE_CHOQUE = 0.95; // choque entre fichas (1 = perfectamente elástico)
float REBOTE_PARED = 0.8;
float UMBRAL_QUIETO = 0.12; // por debajo de esta velocidad la ficha se frena
int MS_FESTEJO = 2500;

// ---------- Estados (máquina de estados) ----------
int ESTADO_MENU = 0;
int ESTADO_ESPERANDO = 1;   // el servidor espera al cliente
int ESTADO_PEDIR_IP = 2;    // el cliente escribe la IP
int ESTADO_CONECTANDO = 3;
int ESTADO_JUGANDO = 4;
int ESTADO_GOL = 5;
int ESTADO_FIN = 6;

// ---------- Roles ----------
int ROL_NINGUNO = 0;
int ROL_LOCAL = 1;
int ROL_HOST = 2;           // servidor: juega el equipo 1
int ROL_CLIENTE = 3;        // cliente: juega el equipo 2

// ---------- Tipos de ficha ----------
int TIPO_JUGADOR = 0;
int TIPO_ARQUERO = 1;
int TIPO_PELOTA = 2;

// ---------- Estado del juego ----------
int estado = 0;
int rol = 0;
int miId = 0;               // 1 = servidor, 2 = cliente, 0 = local
int turno = 1;              // equipo que tiene que tirar
int goles1 = 0;
int goles2 = 0;
int ultimoGoleador = 0;
int tirosEnTurno = 1;       // 1 a MAX_TIROS
boolean tiroRealizado = false;   // ya se tiró y falta que todo se frene
boolean disparoEnviado = false;  // (cliente) ya mandé mi tiro y espero la respuesta
int idxTirador = -1;        // ficha que hizo el tiro de esta jugada
int ultimoToque = -1;       // última ficha que tocó la pelota en esta jugada
int tGol = 0;               // momento del último gol (millis)
int idxSel = -1;            // ficha seleccionada con el mouse (-1 = ninguna)
int avisoCodigo = 0;        // 1 = pase, 2 = sin pase, 3 = máximo de tiros
int tAviso = 0;             // frames que falta mostrar el aviso

// ---------- Camisetas ----------
String[] nombresEquipos = { "River Plate", "Boca Juniors", "Argentina", "Brasil", "Francia", "Alemania" };
PImage[] imgCamisetas;
int menuEquipo = 0;         // camiseta que se está mirando en el menú
int camiseta1 = 0;          // camiseta del equipo 1
int camiseta2 = 1;          // camiseta del equipo 2

// ---------- Objetos ----------
ArrayList<Ficha> fichas;            // 0..5 equipo 1, 6..11 equipo 2, 12 pelota
ArrayList<PVector> postes;          // los 4 palos de los arcos
SistemaParticulas particulas;

// ---------- Red ----------
Red redLan;
String ipTexto = "";
String ipLocal = "";
String mensajeError = "";
boolean equipoEnviado = false;
int tConectando = 0;

// ============================================================
//  CICLO DE VIDA
// ============================================================
void setup() {
  size(1000, 640);                  // size() necesita números literales
  frameRate(60);
  imageMode(CENTER);
  textAlign(CENTER, CENTER);

  golY1 = campoY + (campoAlto - golAlto) / 2.0;
  golY2 = golY1 + golAlto;

  imgCamisetas = new PImage[6];
  for (int i = 0; i < 6; i++) {
    imgCamisetas[i] = crearCamiseta(i);
  }

  // 6 fichas por equipo (la 0 es el arquero) y la pelota (la 12)
  fichas = new ArrayList<Ficha>();
  for (int equipo = 1; equipo <= 2; equipo++) {
    for (int i = 0; i < 6; i++) {
      int tipo = TIPO_JUGADOR;
      if (i == 0) {
        tipo = TIPO_ARQUERO;
      }
      fichas.add(new Ficha(equipo, i, tipo));
    }
  }
  fichas.add(new Ficha(0, 0, TIPO_PELOTA));

  postes = new ArrayList<PVector>();
  postes.add(new PVector(campoX, golY1));
  postes.add(new PVector(campoX, golY2));
  postes.add(new PVector(campoX + campoAncho, golY1));
  postes.add(new PVector(campoX + campoAncho, golY2));

  particulas = new SistemaParticulas();
  estado = ESTADO_MENU;
}

void draw() {
  procesarRed();

  // El cliente no calcula nada: sólo dibuja lo que le manda el servidor
  if ((estado == ESTADO_JUGANDO || estado == ESTADO_GOL) && rol != ROL_CLIENTE) {
    actualizarFisica();
    actualizarReglas();
  }
  if (rol == ROL_HOST && estado >= ESTADO_JUGANDO) {
    enviarPos();
  }
  if (tAviso > 0) {
    tAviso--;
  }
  particulas.actualizar();
  dibujarTodo();
}

// Apaga el hilo de red antes de cerrar la ventana (evita hilos zombi)
void exit() {
  cerrarRed();
  super.exit();
}

// ============================================================
//  FÍSICA Y REGLAS (sólo en el servidor y en el modo local)
// ============================================================
void actualizarFisica() {
  // 1) mover todas las fichas
  for (int i = 0; i < fichas.size(); i++) {
    fichas.get(i).mover();
  }
  // 2) choques entre todos los pares. La pelota es la ficha 12 (la última),
  //    así que si hay choque con j == 12, la ficha i la tocó.
  for (int i = 0; i < fichas.size(); i++) {
    for (int j = i + 1; j < fichas.size(); j++) {
      boolean choco = fichas.get(i).chocarCon(fichas.get(j));
      if (choco && j == 12) {
        ultimoToque = i;
      }
    }
  }
  // 3) palos y paredes
  for (int i = 0; i < fichas.size(); i++) {
    Ficha f = fichas.get(i);
    for (int k = 0; k < postes.size(); k++) {
      f.chocarConPoste(postes.get(k), radioPoste);
    }
    f.rebotarParedes();
  }
}

void actualizarReglas() {
  if (estado == ESTADO_JUGANDO) {
    int anotador = detectarGol();
    if (anotador != 0) {
      registrarGol(anotador);
    } else if (tiroRealizado && !hayMovimiento()) {
      terminarJugada();
    }
  } else if (estado == ESTADO_GOL && millis() - tGol > MS_FESTEJO) {
    if (goles1 >= GOLES_PARA_GANAR || goles2 >= GOLES_PARA_GANAR) {
      estado = ESTADO_FIN;
    } else {
      colocarFormacion();
      estado = ESTADO_JUGANDO;
    }
  }
}

// Se llama cuando todo se frenó después de un tiro.
// PASE = la última ficha que tocó la pelota es un compañero (no el que tiró).
void terminarJugada() {
  tiroRealizado = false;
  boolean pase = false;
  if (ultimoToque >= 0 && ultimoToque != idxTirador) {
    pase = (fichas.get(ultimoToque).equipo == turno);
  }

  if (pase && tirosEnTurno < MAX_TIROS) {
    tirosEnTurno++;                     // pase válido: el mismo equipo vuelve a tirar
    avisar(1);
  } else {
    if (pase) {
      avisar(3);                        // hubo pase pero ya usó los 4 tiros
    } else {
      avisar(2);                        // sin pase
    }
    turno = otroEquipo(turno);
    tirosEnTurno = 1;
  }
}

// Muestra un aviso en pantalla (y el servidor se lo manda al cliente)
void avisar(int codigo) {
  avisoCodigo = codigo;
  tAviso = 150;
  if (rol == ROL_HOST) {
    redLan.enviar("AVISO:" + codigo);
  }
}

String textoAviso() {
  if (avisoCodigo == 1) {
    return "¡Pase! Seguís jugando";
  }
  if (avisoCodigo == 2) {
    return "Sin pase: pasa el turno";
  }
  return "Llegó al máximo de " + MAX_TIROS + " tiros: pasa el turno";
}

// Devuelve el equipo que hizo gol (1 o 2) o 0 si no hubo gol.
// El equipo 1 defiende el arco izquierdo y el equipo 2 el derecho.
int detectarGol() {
  Ficha pelota = fichas.get(12);
  if (pelota.pos.y > golY1 && pelota.pos.y < golY2) {
    if (pelota.pos.x < campoX - pelota.radio) {
      return 2;
    }
    if (pelota.pos.x > campoX + campoAncho + pelota.radio) {
      return 1;
    }
  }
  return 0;
}

void registrarGol(int anotador) {
  if (anotador == 1) {
    goles1++;
  } else {
    goles2++;
  }
  efectoGol(anotador);
  turno = otroEquipo(anotador);         // saca el que recibió el gol
  tirosEnTurno = 1;
  tiroRealizado = false;
  estado = ESTADO_GOL;
  tGol = millis();
}

// Confeti desde la boca del arco donde entró la pelota
void efectoGol(int anotador) {
  ultimoGoleador = anotador;
  float x = campoX;
  if (anotador == 1) {
    x = campoX + campoAncho;
  }
  particulas.explosionGol(x, campoY + campoAlto / 2.0, colorEquipo(anotador));
}

boolean hayMovimiento() {
  for (int i = 0; i < fichas.size(); i++) {
    if (fichas.get(i).vel.magSq() > 0) {
      return true;
    }
  }
  return false;
}

int otroEquipo(int equipo) {
  return 3 - equipo;
}

void colocarFormacion() {
  for (int i = 0; i < fichas.size(); i++) {
    fichas.get(i).reiniciar();
  }
  tiroRealizado = false;
  disparoEnviado = false;
  idxSel = -1;
}

void nuevaPartida() {
  goles1 = 0;
  goles2 = 0;
  turno = 1;
  tirosEnTurno = 1;
  ultimoGoleador = 0;
  tAviso = 0;
  particulas.limpiar();
  colocarFormacion();
  estado = ESTADO_JUGANDO;
}

// ============================================================
//  TIROS (mouse tipo gomera)
// ============================================================
boolean puedoTirar() {
  if (estado != ESTADO_JUGANDO || tiroRealizado || disparoEnviado) {
    return false;
  }
  return rol == ROL_LOCAL || turno == miId;
}

// Equipo que usa el mouse en esta compu
int equipoQueTira() {
  if (rol == ROL_LOCAL) {
    return turno;
  }
  return miId;
}

// Índice de la ficha propia que está bajo el mouse (o -1)
int fichaBajoMouse() {
  int base = (equipoQueTira() - 1) * 6;
  for (int i = 0; i < 6; i++) {
    Ficha f = fichas.get(base + i);
    if (dist(mouseX, mouseY, f.pos.x, f.pos.y) <= f.radio) {
      return base + i;
    }
  }
  return -1;
}

// La velocidad del tiro sale del arrastre: va en sentido contrario al mouse
PVector calcularImpulso(Ficha f) {
  PVector arrastre = new PVector(f.pos.x - mouseX, f.pos.y - mouseY);
  arrastre.limit(MAX_ARRASTRE);
  PVector impulso = PVector.mult(arrastre, FACTOR_TIRO);
  if (f.tipo == TIPO_ARQUERO) {
    impulso.mult(FACTOR_ARQUERO);
  }
  return impulso;
}

void mousePressed() {
  if (manejarBotones()) {
    return;                             // el clic fue en un botón: no es un tiro
  }
  if (puedoTirar()) {
    idxSel = fichaBajoMouse();
  }
}

void mouseReleased() {
  if (idxSel < 0) {
    return;
  }
  Ficha f = fichas.get(idxSel);
  float arrastrado = dist(mouseX, mouseY, f.pos.x, f.pos.y);
  if (arrastrado > 10 && puedoTirar()) {        // si casi no arrastró, se cancela
    lanzar(idxSel, calcularImpulso(f));
  }
  idxSel = -1;
}

void lanzar(int idx, PVector impulso) {
  if (rol == ROL_CLIENTE) {
    // el cliente no mueve nada: le pide al servidor que aplique el tiro
    redLan.enviar("MOV:" + miId + ":" + (idx % 6) + ":" + num(impulso.x) + ":" + num(impulso.y));
    disparoEnviado = true;
  } else {
    aplicarTiro(idx, impulso);
  }
}

void aplicarTiro(int idx, PVector impulso) {
  Ficha f = fichas.get(idx);
  f.vel.set(impulso);
  f.vel.limit(VEL_MAX);
  idxTirador = idx;
  ultimoToque = -1;
  tiroRealizado = true;
}

// ============================================================
//  RED: conexión y mensajes
// ============================================================
void iniciarLocal() {
  mensajeError = "";
  rol = ROL_LOCAL;
  miId = 0;
  camiseta1 = menuEquipo;
  camiseta2 = (menuEquipo + 1) % 6;
  nuevaPartida();
}

void iniciarHost() {
  mensajeError = "";
  redLan = new Red(this, true, "", PUERTO);
  if (redLan.fallo) {
    mensajeError = "No se pudo abrir el puerto " + PUERTO + " (¿ya hay otra partida abierta?)";
    redLan = null;
    return;
  }
  redLan.start();
  rol = ROL_HOST;
  miId = 1;
  camiseta1 = menuEquipo;
  ipLocal = Server.ip();
  estado = ESTADO_ESPERANDO;
}

void conectarCliente() {
  mensajeError = "";
  redLan = new Red(this, false, ipTexto, PUERTO);
  redLan.start();                   // la conexión se intenta dentro del hilo
  rol = ROL_CLIENTE;
  miId = 2;
  equipoEnviado = false;
  tConectando = millis();
  estado = ESTADO_CONECTANDO;
}

void cerrarRed() {
  if (redLan != null) {
    redLan.detener();
  }
  redLan = null;
}

void volverAlMenu() {
  cerrarRed();
  rol = ROL_NINGUNO;
  miId = 0;
  estado = ESTADO_MENU;
  goles1 = 0;
  goles2 = 0;
  turno = 1;
  tirosEnTurno = 1;
  particulas.limpiar();
  colocarFormacion();
}

// Processing llama a esta función cuando un cliente se conecta al servidor
void serverEvent(Server s, Client c) {
  if (redLan != null && redLan.esServidor) {
    redLan.agregarCliente(c);
  }
}

// Se llama en cada frame: saca los mensajes que dejó el hilo de red y los procesa
void procesarRed() {
  if (redLan == null) {
    return;
  }

  ArrayList<String> lista = redLan.tomarMensajes();
  for (int i = 0; i < lista.size(); i++) {
    procesarMensaje(lista.get(i));
  }

  if (rol == ROL_CLIENTE && estado == ESTADO_CONECTANDO) {
    if (redLan.fallo) {
      mensajeError = "No se pudo conectar a " + ipTexto;
      volverAlMenu();
    } else if (redLan.conectado && !equipoEnviado) {
      redLan.enviar("EQUIPO:" + menuEquipo);
      equipoEnviado = true;
    } else if (millis() - tConectando > 10000) {
      mensajeError = "Tiempo agotado: no se pudo conectar a " + ipTexto;
      volverAlMenu();
    }
  } else if (rol == ROL_CLIENTE && redLan.perdido) {
    mensajeError = "Se perdió la conexión con el servidor";
    volverAlMenu();
  } else if (rol == ROL_HOST && estado >= ESTADO_JUGANDO && !redLan.estaConectado()) {
    mensajeError = "El otro jugador se desconectó";
    volverAlMenu();
  }
}

// Mensajes (texto, campos separados por ":"):
//   Cliente -> Servidor
//     EQUIPO:<camiseta>                                   qué camiseta quiere
//     MOV:<id_jugador>:<indice_ficha>:<vx>:<vy>           su tiro
//   Servidor -> Cliente
//     INIT:<camiseta1>:<camiseta2>                        empieza (o reinicia) la partida
//     POS:<estado>:<turno>:<g1>:<g2>:<tiros>:<tiroRealizado>:<x0>:<y0>: ... :<x12>:<y12>
//     AVISO:<codigo>                                      1 pase, 2 sin pase, 3 máximo de tiros
void procesarMensaje(String msg) {
  String[] p = split(msg, ':');

  if (p[0].equals("EQUIPO") && p.length >= 2 && rol == ROL_HOST && estado == ESTADO_ESPERANDO) {
    int c = constrain(parseInt(p[1]), 0, 5);
    if (c == camiseta1) {
      c = (c + 1) % 6;                  // no pueden jugar con la misma camiseta
    }
    camiseta2 = c;
    redLan.enviar("INIT:" + camiseta1 + ":" + camiseta2);
    nuevaPartida();
  } else if (p[0].equals("MOV") && p.length >= 5 && rol == ROL_HOST) {
    int indice = parseInt(p[2]);
    float vx = parseFloat(p[3]);
    float vy = parseFloat(p[4]);
    boolean valido = (turno == 2 && estado == ESTADO_JUGANDO && !tiroRealizado);
    valido = valido && indice >= 0 && indice < 6 && !Float.isNaN(vx) && !Float.isNaN(vy);
    if (valido) {
      aplicarTiro(6 + indice, new PVector(vx, vy));
    }
  } else if (p[0].equals("INIT") && p.length >= 3 && rol == ROL_CLIENTE) {
    camiseta1 = constrain(parseInt(p[1]), 0, 5);
    camiseta2 = constrain(parseInt(p[2]), 0, 5);
    nuevaPartida();
  } else if (p[0].equals("POS") && p.length >= 33 && rol == ROL_CLIENTE) {
    aplicarPos(p);
  } else if (p[0].equals("AVISO") && p.length >= 2 && rol == ROL_CLIENTE) {
    avisoCodigo = parseInt(p[1]);
    tAviso = 150;
  }
}

// El cliente copia el estado que mandó el servidor
void aplicarPos(String[] p) {
  int g1 = parseInt(p[3]);
  int g2 = parseInt(p[4]);
  if (g1 > goles1) {
    efectoGol(1);
  }
  if (g2 > goles2) {
    efectoGol(2);
  }
  goles1 = g1;
  goles2 = g2;
  estado = constrain(parseInt(p[1]), ESTADO_JUGANDO, ESTADO_FIN);
  turno = parseInt(p[2]);
  tirosEnTurno = parseInt(p[5]);
  tiroRealizado = (parseInt(p[6]) == 1);
  for (int i = 0; i < 13; i++) {
    fichas.get(i).pos.set(parseFloat(p[7 + 2 * i]), parseFloat(p[8 + 2 * i]));
  }
  if (tiroRealizado || turno != miId || estado != ESTADO_JUGANDO) {
    disparoEnviado = false;             // ya empezó o terminó mi jugada: puedo volver a tirar
  }
}

// El servidor le manda al cliente el estado completo (en cada frame)
void enviarPos() {
  String m = "POS:" + estado + ":" + turno + ":" + goles1 + ":" + goles2;
  m = m + ":" + tirosEnTurno + ":" + parseInt(tiroRealizado);
  for (int i = 0; i < fichas.size(); i++) {
    Ficha f = fichas.get(i);
    m = m + ":" + num(f.pos.x) + ":" + num(f.pos.y);
  }
  redLan.enviar(m);
}

// Número a texto con 2 decimales. Se usa str() y no nf() porque nf() usa
// la coma decimal en compus configuradas en español y rompería el mensaje.
String num(float v) {
  return str(round(v * 100) / 100.0f);
}

// ============================================================
//  TECLADO
// ============================================================
void keyPressed() {
  if (key == ESC) {
    key = 0;                            // evita que ESC cierre el programa
    volverAlMenu();
    return;
  }

  if (estado == ESTADO_PEDIR_IP) {
    if (key == ENTER || key == RETURN) {
      intentarConectar();
    } else if (key == BACKSPACE && ipTexto.length() > 0) {
      ipTexto = ipTexto.substring(0, ipTexto.length() - 1);
    } else if ((key >= '0' && key <= '9') || key == '.') {
      if (ipTexto.length() < 15) {
        ipTexto = ipTexto + key;
      }
    }
  } else if (estado == ESTADO_FIN && rol != ROL_CLIENTE) {
    if (key == ENTER || key == RETURN) {
      jugarDeNuevo();
    }
  }
}

// ============================================================
//  BOTONES (se usan con el mouse)
//  Cada botón se dibuja con boton() y se detecta con sobre(),
//  usando siempre los mismos números (centro x, centro y, ancho, alto).
// ============================================================
boolean sobre(float cx, float cy, float w, float h) {
  return mouseX > cx - w / 2 && mouseX < cx + w / 2 && mouseY > cy - h / 2 && mouseY < cy + h / 2;
}

void boton(String texto, float cx, float cy, float w, float h) {
  boolean encima = sobre(cx, cy, w, h);
  if (encima) {
    cursor(HAND);
    fill(255, 120, 40);                 // naranja cuando el mouse está encima
    stroke(255, 200, 150);
  } else {
    fill(36, 46, 105);
    stroke(110, 130, 255);
  }
  strokeWeight(3);
  rect(cx - w / 2, cy - h / 2, w, h, 14);
  noStroke();
  if (encima) {
    fill(25, 20, 40);
  } else {
    fill(255);
  }
  textSize(h * 0.4);
  text(texto, cx, cy - 2);
}

// Revisa si el clic fue en algún botón de la pantalla actual. Devuelve true si lo fue.
boolean manejarBotones() {
  float cx = width / 2.0;

  if (estado == ESTADO_MENU) {
    if (sobre(cx - 130, 205, 48, 48)) {
      menuEquipo = (menuEquipo + 5) % 6;
    } else if (sobre(cx + 130, 205, 48, 48)) {
      menuEquipo = (menuEquipo + 1) % 6;
    } else if (sobre(cx, 380, 380, 52)) {
      iniciarHost();
    } else if (sobre(cx, 445, 380, 52)) {
      ipTexto = "";
      mensajeError = "";
      estado = ESTADO_PEDIR_IP;
    } else if (sobre(cx, 510, 380, 52)) {
      iniciarLocal();
    } else {
      return false;
    }
    return true;
  }
  if (estado == ESTADO_PEDIR_IP) {
    if (sobre(cx, 440, 260, 52)) {
      intentarConectar();
      return true;
    }
    if (sobre(cx, 505, 260, 52)) {
      volverAlMenu();
      return true;
    }
    return false;
  }
  if (estado == ESTADO_ESPERANDO || estado == ESTADO_CONECTANDO) {
    if (sobre(cx, 480, 260, 52)) {
      volverAlMenu();
      return true;
    }
    return false;
  }
  if (estado == ESTADO_FIN) {
    if (rol != ROL_CLIENTE && sobre(cx, 500, 260, 52)) {
      jugarDeNuevo();
      return true;
    }
    if (sobre(cx, 565, 260, 52)) {
      volverAlMenu();
      return true;
    }
    return false;
  }
  return false;
}

void intentarConectar() {
  if (ipTexto.length() >= 7) {
    conectarCliente();
  } else {
    mensajeError = "Escribí una IP válida (por ejemplo 192.168.0.15)";
  }
}

void jugarDeNuevo() {
  nuevaPartida();
  if (rol == ROL_HOST) {
    redLan.enviar("INIT:" + camiseta1 + ":" + camiseta2);
  }
}

// ============================================================
//  DIBUJO (sólo se dibuja desde draw(), en el hilo principal)
// ============================================================
void dibujarTodo() {
  cursor(ARROW);
  if (estado == ESTADO_MENU) {
    dibujarMenu();
  } else if (estado == ESTADO_ESPERANDO) {
    dibujarPantalla("Esperando al otro jugador...", ipLocal,
      "Decile que toque \"Unirse a una partida\" y escriba esta IP (puerto " + PUERTO + ").");
    boton("Cancelar", width / 2.0, 480, 260, 52);
  } else if (estado == ESTADO_PEDIR_IP) {
    String barra = "";
    if (frameCount % 60 < 30) {
      barra = "_";
    }
    dibujarPantalla("Unirse a una partida", ipTexto + barra,
      "Escribí la IP del servidor con el teclado y tocá Conectar.");
    boton("Conectar", width / 2.0, 440, 260, 52);
    boton("Volver", width / 2.0, 505, 260, 52);
  } else if (estado == ESTADO_CONECTANDO) {
    dibujarPantalla("Conectando...", ipTexto, "Esperando respuesta del servidor.");
    boton("Cancelar", width / 2.0, 480, 260, 52);
  } else {
    dibujarCancha();
    dibujarFichas();
    dibujarGuia();
    particulas.dibujar();
    dibujarHUD();
    if (estado == ESTADO_GOL) {
      dibujarCartelGol();
    } else if (estado == ESTADO_FIN) {
      dibujarFin();
    }
  }
}

// Fondo de los menús: azul oscuro con unos círculos de adorno
void dibujarFondoMenu() {
  background(14, 17, 40);
  noStroke();
  fill(255, 120, 40, 28);
  ellipse(90, 80, 300, 300);
  fill(110, 130, 255, 30);
  ellipse(930, 560, 420, 420);
  fill(255, 255, 255, 12);
  ellipse(880, 90, 160, 160);
}

void dibujarMenu() {
  dibujarFondoMenu();
  float cx = width / 2.0;

  fill(255);
  textSize(58);
  text("FLICK SOCCER", cx, 62);
  fill(255, 140, 50);
  textSize(24);
  text("L  A  N", cx, 108 - 4);
  stroke(255, 140, 50);
  strokeWeight(3);
  line(cx - 90, 128, cx + 90, 128);
  noStroke();

  // selector de camiseta con dos flechas
  image(imgCamisetas[menuEquipo], cx, 205, 120, 120);
  noFill();
  stroke(255);
  strokeWeight(4);
  ellipse(cx, 205, 120, 120);
  noStroke();
  boton("<", cx - 130, 205, 48, 48);
  boton(">", cx + 130, 205, 48, 48);
  fill(255);
  textSize(26);
  text(nombresEquipos[menuEquipo], cx, 288);
  fill(160, 170, 220);
  textSize(15);
  text("Elegí tu camiseta con las flechas", cx, 316);

  boton("Crear partida (servidor)", cx, 380, 380, 52);
  boton("Unirse a una partida (cliente)", cx, 445, 380, 52);
  boton("Modo local (2 jugadores)", cx, 510, 380, 52);

  dibujarError(575);
}

// Pantalla simple de texto: la usan "esperando", "pedir IP" y "conectando"
void dibujarPantalla(String titulo, String grande, String detalle) {
  dibujarFondoMenu();
  fill(255);
  textSize(40);
  text(titulo, width / 2, 150);
  fill(90, 220, 255);
  textSize(54);
  text(grande, width / 2, 290);
  fill(160, 170, 220);
  textSize(18);
  text(detalle, width / 2, 370);
  dibujarError(580);
}

void dibujarError(float y) {
  if (mensajeError.length() > 0) {
    fill(255, 100, 100);
    textSize(18);
    text(mensajeError, width / 2, y);
  }
}

void dibujarCancha() {
  background(24, 70, 40);

  // césped a franjas
  noStroke();
  for (int i = 0; i < 10; i++) {
    if (i % 2 == 0) {
      fill(46, 150, 60);
    } else {
      fill(40, 136, 54);
    }
    rect(campoX + i * campoAncho / 10.0, campoY, campoAncho / 10.0 + 1, campoAlto);
  }

  // los dos arcos (fuera de la cancha) con su red
  fill(255, 40);
  rect(campoX - golProf, golY1, golProf, golAlto);
  rect(campoX + campoAncho, golY1, golProf, golAlto);
  stroke(255, 90);
  strokeWeight(1);
  for (int i = 0; i <= golProf; i += 10) {
    line(campoX - i, golY1, campoX - i, golY2);
    line(campoX + campoAncho + i, golY1, campoX + campoAncho + i, golY2);
  }
  for (float y = golY1; y <= golY2; y += 15) {
    line(campoX - golProf, y, campoX, y);
    line(campoX + campoAncho, y, campoX + campoAncho + golProf, y);
  }

  // líneas de la cancha
  float cx = campoX + campoAncho / 2.0;
  float cy = campoY + campoAlto / 2.0;
  noFill();
  stroke(255);
  strokeWeight(3);
  rect(campoX, campoY, campoAncho, campoAlto);
  line(cx, campoY, cx, campoY + campoAlto);
  ellipse(cx, cy, 140, 140);
  rect(campoX, cy - 130, 130, 260);
  rect(campoX + campoAncho - 130, cy - 130, 130, 260);

  // palos
  noStroke();
  fill(255);
  for (int i = 0; i < postes.size(); i++) {
    PVector poste = postes.get(i);
    ellipse(poste.x, poste.y, radioPoste * 2, radioPoste * 2);
  }
}

void dibujarFichas() {
  boolean activo = puedoTirar();
  for (int i = 0; i < fichas.size(); i++) {
    Ficha f = fichas.get(i);
    f.dibujar(activo && f.equipo == equipoQueTira());   // las que se pueden tirar tienen halo
  }
  if (activo && fichaBajoMouse() >= 0) {
    cursor(HAND);
  }
}

// Gomera: línea hacia donde se estira y línea guía hacia donde saldrá el tiro
void dibujarGuia() {
  if (idxSel < 0) {
    return;
  }
  Ficha f = fichas.get(idxSel);
  PVector arrastre = new PVector(f.pos.x - mouseX, f.pos.y - mouseY);
  arrastre.limit(MAX_ARRASTRE);
  float fuerza = arrastre.mag() / MAX_ARRASTRE;     // de 0 a 1

  stroke(255, 200);
  strokeWeight(3);
  line(f.pos.x, f.pos.y, f.pos.x - arrastre.x, f.pos.y - arrastre.y);

  if (arrastre.mag() > 10) {
    float largo = 40 + fuerza * 170;
    PVector fin = PVector.add(f.pos, PVector.mult(arrastre.copy().normalize(), largo));
    color c = lerpColor(color(80, 230, 80), color(255, 60, 60), fuerza);   // verde = flojo, rojo = fuerte
    stroke(c);
    strokeWeight(4);
    line(f.pos.x, f.pos.y, fin.x, fin.y);
    noStroke();
    fill(c);
    ellipse(fin.x, fin.y, 14, 14);
  }
}

void dibujarHUD() {
  noStroke();
  fill(0, 160);
  rect(0, 0, width, 80);
  dibujarEquipoHUD(1, 50, LEFT, 85);
  dibujarEquipoHUD(2, width - 50, RIGHT, width - 85);

  // marcador y turno
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(44);
  text(goles1 + "  -  " + goles2, width / 2, 30);
  if (estado == ESTADO_JUGANDO) {
    String quien = "Turno de " + nombreEquipo(turno);
    if (rol != ROL_LOCAL && turno == miId) {
      quien = "¡Es tu turno!";
    }
    fill(colorEquipo(turno));
    textSize(17);
    text(quien + "   -   tiro " + tirosEnTurno + " de " + MAX_TIROS, width / 2, 66);
  }

  // aviso de pase
  if (tAviso > 0 && estado == ESTADO_JUGANDO) {
    fill(0, 170);
    rect(width / 2 - 250, 98, 500, 36, 8);
    fill(255, 230, 0);
    textSize(20);
    text(textoAviso(), width / 2, 117);
  }

  // ayuda abajo
  fill(255, 210);
  textSize(14);
  text("Arrastrá una ficha hacia atrás y soltá. Pase a un compañero = seguís (máx. 4 tiros). Aro dorado = arquero. Meta: 5 goles.", width / 2, 626);
}

// Camiseta y nombre de un equipo en la barra de arriba
void dibujarEquipoHUD(int equipo, float xImagen, int alineacion, float xTexto) {
  image(imgCamisetas[camisetaDe(equipo)], xImagen, 38, 46, 46);
  noFill();
  stroke(colorEquipo(equipo));
  strokeWeight(4);
  ellipse(xImagen, 38, 46, 46);

  noStroke();
  textAlign(alineacion, CENTER);
  fill(255);
  textSize(20);
  text(nombreEquipo(equipo), xTexto, 30);

  String etiqueta = "";
  if (rol == ROL_HOST && equipo == 1) {
    etiqueta = "Vos sos el servidor";
  } else if (rol == ROL_CLIENTE && equipo == 2) {
    etiqueta = "Vos sos el cliente";
  } else if (rol == ROL_LOCAL && equipo == 1) {
    etiqueta = "Modo local";
  }
  fill(190);
  textSize(13);
  text(etiqueta, xTexto, 58);
  textAlign(CENTER, CENTER);
}

void dibujarCartelGol() {
  noStroke();
  fill(0, 120);
  rect(0, 235, width, 170);
  fill(255, 215, 0);
  textSize(96);
  text("¡Gooooooool!", width / 2, 305);
  fill(255);
  textSize(28);
  text(nombreEquipo(ultimoGoleador), width / 2, 375);
}

void dibujarFin() {
  noStroke();
  fill(0, 190);
  rect(0, 0, width, height);
  fill(255);
  textSize(40);
  text("FIN DEL PARTIDO", width / 2, 190);
  textSize(72);
  text(goles1 + "  -  " + goles2, width / 2, 270);
  int ganador = 1;
  if (goles2 > goles1) {
    ganador = 2;
  }
  fill(colorEquipo(ganador));
  textSize(46);
  text("¡Ganó " + nombreEquipo(ganador) + "!", width / 2, 360);
  if (rol == ROL_CLIENTE) {
    fill(255, 215);
    textSize(18);
    text("Esperando que el servidor empiece otra partida", width / 2, 450);
  } else {
    boton("Jugar de nuevo", width / 2.0, 500, 260, 52);
  }
  boton("Volver al menú", width / 2.0, 565, 260, 52);
}

// ============================================================
//  CAMISETAS (se dibujan por código, una sola vez, en setup)
//  0 River Plate   1 Boca Juniors   2 Argentina
//  3 Brasil        4 Francia        5 Alemania
// ============================================================
PImage crearCamiseta(int tipo) {
  int t = 100;
  PGraphics pg = createGraphics(t, t);
  pg.beginDraw();
  pg.noStroke();

  if (tipo == 0) {
    // River: blanco con banda diagonal roja
    pg.background(255);
    pg.stroke(215, 20, 40);
    pg.strokeWeight(32);
    pg.line(-10, -10, t + 10, t + 10);
  } else if (tipo == 1) {
    // Boca: azul con franja horizontal amarilla
    pg.background(0, 45, 130);
    pg.fill(255, 205, 0);
    pg.rect(0, 35, t, 30);
  } else if (tipo == 2) {
    // Argentina: blanco con tres bastones verticales celestes
    pg.background(255);
    pg.fill(117, 172, 220);
    pg.rect(8, 0, 20, t);
    pg.rect(40, 0, 20, t);
    pg.rect(72, 0, 20, t);
  } else if (tipo == 3) {
    // Brasil: amarillo con detalles verdes
    pg.background(255, 220, 0);
    pg.fill(0, 140, 60);
    pg.rect(0, 0, t, 14);
    pg.rect(0, t - 14, t, 14);
    pg.rect(0, 0, 8, t);
    pg.rect(t - 8, 0, 8, t);
  } else if (tipo == 4) {
    // Francia: azul con franja roja arriba
    pg.background(0, 50, 150);
    pg.fill(220, 30, 50);
    pg.rect(0, 0, t, 30);
  } else {
    // Alemania: blanco con las franjas de la bandera abajo
    pg.background(255);
    pg.fill(0);
    pg.rect(0, 58, t, 14);
    pg.fill(221, 0, 0);
    pg.rect(0, 72, t, 14);
    pg.fill(255, 206, 0);
    pg.rect(0, 86, t, 14);
  }
  pg.endDraw();

  // máscara circular: la camiseta queda con forma de ficha
  PGraphics mascara = createGraphics(t, t);
  mascara.beginDraw();
  mascara.background(0);
  mascara.noStroke();
  mascara.fill(255);
  mascara.ellipse(t / 2.0, t / 2.0, t - 2, t - 2);
  mascara.endDraw();

  PImage img = pg.get();
  img.mask(mascara.get());
  return img;
}

// ============================================================
//  UTILIDADES
// ============================================================
int camisetaDe(int equipo) {
  if (equipo == 1) {
    return camiseta1;
  }
  return camiseta2;
}

String nombreEquipo(int equipo) {
  return nombresEquipos[camisetaDe(equipo)];
}

color colorEquipo(int equipo) {
  if (equipo == 1) {
    return color(230, 60, 60);
  }
  return color(60, 130, 240);
}
