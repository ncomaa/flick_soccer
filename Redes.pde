/*
 * ============================================================
 *  PESTAÑA: Redes.pde
 * ============================================================
 *  Una sola clase, Red, que hereda de Thread. Sirve para los dos lados:
 *    - esServidor = true : escucha, guarda el cliente en un ArrayList<Client>
 *    - esServidor = false: se conecta al servidor (dentro del hilo)
 *
 *  Por qué un hilo: leer de la red puede tardar y si se hiciera en draw()
 *  el juego se congelaría. El hilo lee en segundo plano y deja cada mensaje
 *  en una lista; draw() la vacía en cada frame con tomarMensajes().
 *
 *  Reglas:
 *    - El hilo NO dibuja ni toca el estado del juego: sólo guarda texto.
 *    - volatile boolean corriendo: bandera de vida; "volatile" hace que
 *      todos los hilos vean siempre el valor actualizado.
 *    - synchronized (candado): protege las listas para que el hilo de red
 *      y draw() no las usen a la vez.
 *    - detener(): apaga el hilo y cierra los sockets (lo llama exit()).
 *
 *  Mensajes: una línea de texto terminada en salto de línea, con los
 *  campos separados por ":".
 * ============================================================
 */

import processing.net.*;

class Red extends Thread {
  volatile boolean corriendo;           // bandera de vida del hilo
  Object candado;                       // cerrojo para synchronized
  ArrayList<String> mensajes;           // mensajes recibidos sin procesar
  ArrayList<Client> clientes;           // servidor: clientes / cliente: sólo uno

  boolean esServidor;
  Server servidor;
  PApplet app;
  String ip;
  int puerto;
  volatile boolean conectado;           // el cliente ya se conectó
  volatile boolean fallo;               // no se pudo abrir el puerto / conectar
  volatile boolean perdido;             // se cayó la conexión

  Red(PApplet appNueva, boolean soyServidor, String ipServidor, int puertoRed) {
    corriendo = true;
    candado = new Object();
    mensajes = new ArrayList<String>();
    clientes = new ArrayList<Client>();
    esServidor = soyServidor;
    app = appNueva;
    ip = ipServidor;
    puerto = puertoRed;
    conectado = false;
    fallo = false;
    perdido = false;
    setDaemon(true);                    // si se cierra el programa, el hilo no lo retiene

    if (esServidor) {
      servidor = new Server(app, puerto);
      fallo = !servidor.active();       // puerto ocupado = no queda activo
    }
  }

  public void run() {
    if (!esServidor) {
      // Conectar puede tardar si la IP no responde: por eso va dentro del hilo
      Client c = new Client(app, ip, puerto);
      if (!c.active()) {
        fallo = true;
        corriendo = false;
        return;
      }
      synchronized (candado) {
        clientes.add(c);
      }
      conectado = true;
    }

    while (corriendo) {
      leer();
      try {
        Thread.sleep(2);                // descansa 2 ms para no gastar CPU
      } catch (InterruptedException e) {
        corriendo = false;
      }
    }
  }

  // Lee una línea de algún cliente que tenga datos (servidor) o del servidor (cliente)
  void leer() {
    Client c = null;
    if (esServidor) {
      c = servidor.available();
    } else {
      synchronized (candado) {
        if (clientes.size() > 0) {
          c = clientes.get(0);
        }
      }
      if (c != null && !c.active()) {
        perdido = true;
        conectado = false;
        corriendo = false;
        return;
      }
    }
    if (c != null && c.available() > 0) {
      String linea = c.readStringUntil('\n');
      if (linea != null) {              // null = todavía no llegó la línea completa
        synchronized (candado) {
          mensajes.add(trim(linea));
        }
      }
    }
  }

  // Processing avisa (serverEvent) cuando alguien se conecta al servidor
  void agregarCliente(Client c) {
    synchronized (candado) {
      limpiarDesconectados();
      if (clientes.size() < 1) {        // el juego es de 2: entra un solo cliente
        clientes.add(c);
      } else {
        c.stop();
      }
    }
  }

  // Se recorre de atrás hacia adelante para poder borrar sin errores
  void limpiarDesconectados() {
    for (int i = clientes.size() - 1; i >= 0; i--) {
      if (!clientes.get(i).active()) {
        clientes.remove(i);
      }
    }
  }

  // Lo llama draw(): devuelve todos los mensajes pendientes y vacía la cola
  ArrayList<String> tomarMensajes() {
    ArrayList<String> copia = new ArrayList<String>();
    synchronized (candado) {
      for (int i = 0; i < mensajes.size(); i++) {
        copia.add(mensajes.get(i));
      }
      mensajes.clear();
    }
    return copia;
  }

  void enviar(String m) {
    synchronized (candado) {
      for (int i = 0; i < clientes.size(); i++) {
        clientes.get(i).write(m + "\n");
      }
    }
  }

  boolean estaConectado() {
    synchronized (candado) {
      limpiarDesconectados();
      return clientes.size() > 0;
    }
  }

  void detener() {
    corriendo = false;
    interrupt();                        // despierta al hilo si estaba durmiendo
    synchronized (candado) {
      for (int i = 0; i < clientes.size(); i++) {
        clientes.get(i).stop();
      }
      clientes.clear();
    }
    if (servidor != null) {
      servidor.stop();
    }
  }
}
