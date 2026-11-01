import 'package:flutter/material.dart';

/// Pantalla de lectura de los términos y condiciones de AniMap.
/// No modifica el registro ni acepta documentos automáticamente.
class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentPage(
      pageTitle: 'Términos y condiciones',
      documentTitle: 'TÉRMINOS Y CONDICIONES DE USO',
      sections: _termsSections,
    );
  }
}

/// Pantalla de lectura de la política de privacidad de AniMap.
/// No solicita ni guarda consentimiento por sí sola.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentPage(
      pageTitle: 'Política de privacidad',
      documentTitle: 'POLÍTICA DE PRIVACIDAD Y TRATAMIENTO DE DATOS PERSONALES',
      sections: _privacySections,
    );
  }
}

/// Diseño común para ambos documentos, sin dependencias adicionales.
class _LegalDocumentPage extends StatelessWidget {
  const _LegalDocumentPage({
    required this.pageTitle,
    required this.documentTitle,
    required this.sections,
  });

  final String pageTitle;
  final String documentTitle;
  final List<_LegalSection> sections;

  static const _background = Color(0xFFDDE6D8);
  static const _green = Color(0xFF3F9E57);
  static const _text = Color(0xFF415466);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          pageTitle,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Scrollbar(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFC8D1C3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.pets, color: _green, size: 23),
                            SizedBox(width: 8),
                            Text(
                              'AniMap',
                              style: TextStyle(
                                color: _green,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          documentTitle,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Versión 1.0 — Borrador para revisión\n'
                          'Proyecto de grado · Universidad Manuela Beltrán\n'
                          'Bogotá D. C., Colombia',
                          style: TextStyle(color: _text, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3E8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Documento académico en revisión. Antes de usarlo '
                            'con usuarios reales deben completarse los datos '
                            'legales pendientes.',
                            style: TextStyle(color: _text, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(),
                        for (final section in sections) ...[
                          const SizedBox(height: 14),
                          Text(
                            section.heading,
                            style: const TextStyle(
                              color: _green,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            section.body.trim(),
                            style: const TextStyle(
                              color: _text,
                              fontSize: 14,
                              height: 1.55,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Divider(),
                        const Text(
                          'AniMap — Proyecto de grado de Ingeniería de Software\n'
                          'Universidad Manuela Beltrán · Bogotá, Colombia',
                          style: TextStyle(color: _text, fontSize: 12, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

const List<_LegalSection> _termsSections = [
  _LegalSection('1. Introducción', '''
Bienvenido a AniMap.

AniMap es un prototipo de aplicación móvil desarrollado como proyecto de grado por estudiantes de Ingeniería de Software de la Universidad Manuela Beltrán.

Su propósito es facilitar el registro de mascotas, la publicación de reportes de pérdida y avistamientos, y la colaboración entre los miembros de la comunidad para apoyar la búsqueda de animales extraviados.

El proyecto tiene como zona piloto el barrio Ciudad Salitre Occidental de Bogotá D. C.

Al registrarse y utilizar AniMap, el usuario declara haber leído y aceptado los presentes términos y condiciones de uso.
'''),
  _LegalSection('2. Objetivo de la aplicación', '''
AniMap busca proporcionar una herramienta tecnológica que facilite la comunicación entre propietarios de mascotas y personas que puedan aportar información sobre animales extraviados.

Entre sus funcionalidades previstas se encuentran:

• Registro y administración de perfiles de mascotas.
• Publicación y consulta de reportes de mascotas perdidas.
• Registro de avistamientos realizados por la comunidad.
• Visualización de reportes mediante un mapa interactivo.
• Notificaciones relacionadas con pérdidas y avistamientos.
• Herramientas de apoyo para identificar posibles coincidencias entre mascotas.

Estas funcionalidades estarán disponibles de acuerdo con el avance y las características habilitadas en cada versión del prototipo.

AniMap no garantiza la recuperación de mascotas, sino que funciona como una herramienta de apoyo para facilitar su búsqueda.
'''),
  _LegalSection('3. Registro y cuentas de usuario', '''
Para utilizar las funcionalidades que requieren identificación, el usuario deberá crear una cuenta proporcionando los datos solicitados en el formulario de registro.

El usuario se compromete a:

• Proporcionar información verídica y actualizada.
• Utilizar un correo electrónico al que tenga acceso.
• Mantener la confidencialidad de sus credenciales.
• No utilizar cuentas de otras personas sin autorización.
• Informar al equipo responsable cuando identifique un uso no autorizado de su cuenta.

AniMap podrá implementar mecanismos de verificación de correo electrónico, recuperación de contraseña y administración de sesiones para fortalecer la seguridad de las cuentas.
'''),
  _LegalSection('4. Registro de mascotas', '''
Los usuarios podrán registrar mascotas asociadas a sus cuentas, proporcionando características como nombre, especie, raza, color, sexo, fotografías y señas particulares.

El propietario será responsable de que la información registrada sea correcta y de que las imágenes utilizadas correspondan a la mascota.

Los usuarios deberán respetar las validaciones y los campos obligatorios establecidos en la aplicación.

La información podrá actualizarse mediante las funciones de edición disponibles.
'''),
  _LegalSection('5. Reportes de pérdida y avistamientos', '''
AniMap permitirá publicar información relacionada con mascotas extraviadas y animales avistados.

Los usuarios se comprometen a:

• Registrar información verdadera sobre la pérdida o el avistamiento.
• Proporcionar ubicaciones relacionadas con el evento reportado.
• No publicar reportes falsos o engañosos.
• Evitar registrar contenido duplicado de manera intencional.
• Actualizar o finalizar sus reportes cuando corresponda.
• Respetar la privacidad de los demás usuarios.

Los reportes podrán contener fotografías, descripciones, fechas y ubicaciones que serán utilizadas para apoyar la identificación y búsqueda de mascotas.
'''),
  _LegalSection('6. Fotografías y contenido publicado', '''
Al cargar fotografías, descripciones o información sobre una mascota, el usuario declara que cuenta con los derechos o autorizaciones necesarios para utilizar dicho contenido.

El usuario autoriza que el contenido relacionado con sus reportes sea presentado dentro de AniMap exclusivamente para las finalidades propias de la plataforma.

No se permite publicar imágenes, información personal de terceros ni contenido que vulnere derechos de otras personas.

El equipo encargado de AniMap podrá retirar contenido que incumpla estas condiciones, respetando los procedimientos aplicables.
'''),
  _LegalSection('7. Uso de la ubicación geográfica', '''
AniMap podrá solicitar acceso a la ubicación del dispositivo para facilitar la creación de reportes y avistamientos.

El acceso a la ubicación requerirá los permisos correspondientes del dispositivo.

Cuando la funcionalidad esté disponible, el usuario podrá seleccionar un punto en el mapa o proporcionar una ubicación manualmente.

Las ubicaciones asociadas a reportes podrán mostrarse a otros usuarios para facilitar la búsqueda de mascotas. El alcance de esta visualización y el tratamiento de dichos datos se explicarán en la Política de privacidad.

La precisión de la ubicación puede variar según el dispositivo, la conexión y el método de registro utilizado.
'''),
  _LegalSection('8. Uso adecuado de AniMap', '''
El usuario se compromete a utilizar la aplicación de manera responsable y respetuosa.

Está prohibido:

• Publicar información falsa con intención de engañar.
• Suplantar la identidad de otros usuarios.
• Utilizar la plataforma para acosar, amenazar o perjudicar a otras personas.
• Difundir información privada de terceros sin autorización.
• Intentar acceder sin permiso a cuentas, sistemas o información.
• Utilizar la aplicación para actividades contrarias a la legislación vigente.

El incumplimiento de estas condiciones podrá dar lugar a medidas de moderación, restricción de funcionalidades o suspensión de la cuenta, según la gravedad de la situación.
'''),
  _LegalSection('9. Notificaciones y comunicaciones', '''
AniMap podrá enviar notificaciones relacionadas con reportes de pérdida, avistamientos, posibles coincidencias y avisos importantes sobre la aplicación.

La recepción de notificaciones dependerá de los permisos otorgados por el usuario, la disponibilidad del servicio y las funcionalidades implementadas.

Las notificaciones tienen carácter informativo y no garantizan la recepción inmediata de cada alerta.
'''),
  _LegalSection('10. Privacidad y protección de datos personales', '''
AniMap reconoce la importancia de la privacidad y del tratamiento responsable de la información de sus usuarios.

Los datos personales serán tratados de acuerdo con las finalidades informadas en la Política de privacidad y tratamiento de datos personales y las autorizaciones correspondientes.

Los usuarios podrán ejercer los derechos que les reconozca la legislación colombiana, incluyendo conocer, actualizar, rectificar y solicitar la supresión de sus datos, cuando proceda.

La aceptación de estos términos y condiciones no reemplaza la autorización para el tratamiento de datos personales cuando esta sea legalmente necesaria.

Para obtener información detallada sobre el uso de los datos, el usuario deberá consultar el documento independiente denominado Política de privacidad de AniMap.
'''),
  _LegalSection('11. Seguridad y disponibilidad', '''
AniMap contempla mecanismos de seguridad para proteger las cuentas y la información registrada.

Debido a que se trata de un prototipo académico en desarrollo, algunas funcionalidades podrán estar temporalmente limitadas o no disponibles durante pruebas, mantenimiento y actualizaciones.

El equipo de desarrollo procurará corregir los errores identificados y mejorar progresivamente el funcionamiento y la seguridad de la aplicación.
'''),
  _LegalSection('12. Limitaciones del servicio', '''
AniMap constituye una herramienta de colaboración comunitaria y no un servicio profesional de búsqueda o recuperación de animales.

La aplicación no puede garantizar la autenticidad de toda la información proporcionada por terceros ni asegurar que una mascota reportada sea encontrada.

Los usuarios deben actuar con precaución al compartir información, contactar a otras personas o acudir a ubicaciones relacionadas con reportes.

Estas condiciones no excluyen las responsabilidades que puedan corresponder legalmente a quienes operan el servicio.
'''),
  _LegalSection('13. Suspensión y eliminación de cuentas', '''
Los usuarios podrán solicitar la eliminación de sus cuentas y datos personales mediante los mecanismos habilitados por la aplicación o el canal de contacto correspondiente.

Los administradores podrán suspender cuentas o moderar contenido cuando se identifiquen incumplimientos de los términos de uso.

Las solicitudes de eliminación y supresión se atenderán de acuerdo con la Política de privacidad y las obligaciones legales aplicables.
'''),
  _LegalSection('14. Modificaciones de los términos', '''
Los presentes términos y condiciones podrán actualizarse cuando se incorporen nuevas funcionalidades, cambien las condiciones de funcionamiento o sea necesario adaptar el documento a disposiciones legales.

Los cambios relevantes serán informados a los usuarios mediante los canales disponibles y, cuando corresponda, se solicitará una nueva aceptación.
'''),
  _LegalSection('15. Contacto y soporte', '''
Para consultas relacionadas con el uso de AniMap o sus condiciones de funcionamiento, los usuarios podrán comunicarse a través del siguiente canal:

Correo de contacto: [Pendiente de confirmar]

Responsable del proyecto y del tratamiento de datos: [Pendiente de identificación formal]

Ciudad: Bogotá D. C., Colombia.
'''),
  _LegalSection('16. Aceptación de términos y condiciones', '''
Antes de completar su registro, el usuario deberá tener acceso a los términos y condiciones y a la Política de privacidad de AniMap.

La aplicación solicitará una aceptación expresa de los documentos correspondientes. Si el usuario no acepta las condiciones obligatorias para crear una cuenta, el registro no podrá finalizarse.

La autorización para el tratamiento de datos personales deberá obtenerse mediante un mecanismo que informe claramente las finalidades del tratamiento y permita conservar evidencia de dicha autorización.
'''),
];

const List<_LegalSection> _privacySections = [
  _LegalSection('1. Introducción', '''
AniMap es un prototipo de aplicación móvil desarrollado como proyecto de grado por estudiantes de Ingeniería de Software de la Universidad Manuela Beltrán.

Su propósito es facilitar el registro de mascotas, la publicación de reportes de pérdida y avistamientos, y la colaboración comunitaria para apoyar la búsqueda de animales extraviados, principalmente en la zona piloto de Ciudad Salitre Occidental, Bogotá D. C.

Esta Política de privacidad explica qué datos personales puede recopilar AniMap, para qué se utilizan, cómo se almacenan, quién puede acceder a ellos y cuáles son los derechos de los usuarios.

El tratamiento de los datos personales deberá realizarse conforme a la Ley 1581 de 2012 y las demás disposiciones aplicables en Colombia.
'''),
  _LegalSection('2. Responsable del tratamiento de datos', '''
El proyecto AniMap es desarrollado en el marco de una actividad académica de la Universidad Manuela Beltrán.

Los datos de identificación del responsable del tratamiento deberán definirse formalmente antes de utilizar el prototipo con usuarios reales.

Información pendiente de completar:

• Responsable del tratamiento: [Nombre de la persona o entidad responsable].
• Dirección de contacto: [Dirección física].
• Ciudad: Bogotá D. C., Colombia.
• Correo electrónico: [Correo oficial de privacidad o soporte].
• Teléfono: [Número de contacto].
• Área o persona encargada de las solicitudes: [Responsable designado].

La vinculación académica con la Universidad Manuela Beltrán no implica por sí sola que esta asuma la responsabilidad del tratamiento de datos.
'''),
  _LegalSection('3. Información que recopila AniMap', '''
Dependiendo de las funcionalidades utilizadas, AniMap podrá recopilar y almacenar las siguientes categorías de información:

3.1. Datos de registro y cuenta
• Nombre del usuario.
• Correo electrónico.
• Número de teléfono.
• Contraseña protegida mediante un mecanismo de hashing.
• Fecha de registro y estado de verificación de la cuenta.
• Rol y estado de la cuenta.
• Información necesaria para gestionar la autenticación y las sesiones.

3.2. Información de mascotas
• Nombre de la mascota.
• Especie y raza.
• Color, sexo y características físicas.
• Fotografías proporcionadas por el usuario.
• Observaciones o señas particulares.
• Estado de la mascota dentro de la aplicación.

3.3. Información de reportes y avistamientos
• Descripción de la pérdida o avistamiento.
• Fotografías asociadas al reporte.
• Fecha y hora del evento.
• Ubicación geográfica del reporte.
• Estado e historial de los reportes.
• Identificador del usuario que publica la información.

3.4. Datos de ubicación
Cuando el usuario utilice funcionalidades de geolocalización, AniMap podrá procesar coordenadas geográficas obtenidas mediante GPS, selección manual de un punto en el mapa o ingreso de una dirección.

3.5. Datos técnicos y de seguridad
Para el funcionamiento de los mecanismos de autenticación, la aplicación podrá procesar identificadores de dispositivo, datos de sesión, fechas de acceso y registros técnicos necesarios para la seguridad del servicio.

Solo deberán recopilarse los datos necesarios para las funcionalidades efectivamente habilitadas.
'''),
  _LegalSection('4. Finalidad del tratamiento de datos', '''
La información recopilada tendrá las siguientes finalidades:

1. Crear, verificar y administrar las cuentas de los usuarios.
2. Permitir el inicio y cierre de sesión.
3. Gestionar los perfiles y la información de las mascotas registradas.
4. Crear, consultar, actualizar y finalizar reportes de pérdida.
5. Registrar avistamientos de mascotas.
6. Mostrar en el mapa las ubicaciones relacionadas con los reportes.
7. Enviar notificaciones relacionadas con pérdidas, avistamientos y posibles coincidencias cuando esta funcionalidad se encuentre habilitada.
8. Prevenir usos indebidos de la aplicación y gestionar la seguridad de las cuentas.
9. Atender consultas y solicitudes relacionadas con el funcionamiento de AniMap.
10. Realizar pruebas funcionales y evaluar el prototipo dentro del proyecto académico, aplicando medidas para minimizar el uso de información identificable.

Los datos personales no serán utilizados para fines publicitarios o comerciales ajenos a los objetivos informados de AniMap sin la autorización correspondiente.

Cuando se desarrollen nuevas funcionalidades que impliquen finalidades diferentes, estas deberán comunicarse y, cuando sea necesario, requerir una nueva autorización.
'''),
  _LegalSection('5. Autorización para el tratamiento de datos', '''
Antes de completar el registro, AniMap deberá presentar al usuario los Términos y condiciones y la presente Política de privacidad.

El usuario deberá poder consultar los documentos y manifestar su decisión de manera libre, previa, expresa e informada.

La autorización para el tratamiento de datos personales se solicitará de forma diferenciada de la aceptación de los Términos y condiciones, mediante un mecanismo verificable.

El sistema deberá conservar evidencia de la autorización otorgada, incluyendo la identificación del usuario, la fecha y la versión del texto autorizado.

Si el usuario no autoriza el tratamiento de los datos indispensables para crear y administrar su cuenta, el sistema no podrá completar el registro.

Los permisos opcionales del dispositivo, como el acceso a la ubicación y las notificaciones, se solicitarán cuando sean necesarios y podrán gestionarse mediante las opciones disponibles en el sistema operativo.
'''),
  _LegalSection('6. Tratamiento de datos de ubicación', '''
AniMap utilizará información geográfica para facilitar la publicación y consulta de reportes de mascotas perdidas y avistamientos.

Antes de acceder a la ubicación del dispositivo, la aplicación deberá solicitar los permisos correspondientes.

Cuando exista una alternativa manual disponible, el usuario podrá registrar el punto del evento sin utilizar su ubicación actual.

Las coordenadas asociadas a un reporte podrán ser visibles para otros usuarios a través del mapa interactivo, según las características de publicación implementadas.

Por este motivo, se informará al usuario cuando una ubicación vaya a formar parte de un reporte visible para la comunidad.

AniMap no deberá utilizar la ubicación del dispositivo para realizar un seguimiento permanente de sus usuarios sin una finalidad legítima, información suficiente y la autorización correspondiente.
'''),
  _LegalSection('7. Fotografías y contenido compartido', '''
Las fotografías de mascotas se utilizarán para facilitar su identificación y apoyar la búsqueda de animales extraviados.

Los usuarios serán responsables de publicar imágenes relacionadas con las finalidades de AniMap y de contar con las autorizaciones necesarias.

Las imágenes asociadas a perfiles y reportes podrán ser consultadas por otros usuarios de acuerdo con los permisos y la visibilidad establecidos en la aplicación.

AniMap deberá evitar la divulgación innecesaria de información personal que aparezca accidentalmente en imágenes o descripciones.

En caso de habilitarse funciones de reconocimiento y comparación automática de fotografías, esta política deberá revisarse para explicar el funcionamiento, los datos analizados y las finalidades de dicho procesamiento.
'''),
  _LegalSection('8. Almacenamiento de información', '''
La arquitectura definida para AniMap contempla:

• PostgreSQL en Google Cloud SQL: almacenamiento de la información estructurada, como usuarios, mascotas, sesiones y reportes.
• MongoDB: almacenamiento de imágenes asociadas a mascotas y otras funcionalidades del prototipo.
• Backend Node.js y Express: procesamiento de solicitudes entre la aplicación móvil y las bases de datos.

La infraestructura podrá modificarse durante el desarrollo del proyecto, siempre que se respeten las finalidades informadas y las obligaciones de protección de datos.

Antes del uso con participantes reales, se deberá verificar dónde se alojan las imágenes, qué proveedores procesan información personal y qué medidas de seguridad y respaldo se encuentran efectivamente habilitadas.
'''),
  _LegalSection('9. Seguridad de la información', '''
AniMap contempla la aplicación de medidas técnicas y organizativas destinadas a proteger los datos personales frente a accesos no autorizados, alteraciones, pérdidas o divulgaciones indebidas.

Estas medidas incluyen, según su estado de implementación y validación:

• Protección de contraseñas mediante hashing seguro.
• Autenticación y control de acceso según roles.
• Restricción de las funciones administrativas.
• Gestión y cierre seguro de sesiones.
• Uso de HTTPS/TLS para comunicaciones de producción.
• Acceso controlado a los datos almacenados.
• Validación de información recibida por el backend.

Durante la fase de desarrollo podrán existir configuraciones locales de prueba. Estas deberán revisarse y reforzarse antes de permitir el tratamiento de información real mediante una versión publicada de la aplicación.

Ningún mecanismo de seguridad elimina por completo los riesgos tecnológicos, por lo que se realizarán revisiones y correcciones cuando se identifiquen vulnerabilidades.
'''),
  _LegalSection('10. Acceso y divulgación de información', '''
La información personal será accesible únicamente para quienes la necesiten conforme a sus funciones y autorizaciones.

Podrán existir diferentes niveles de acceso:

Usuario registrado: acceso a su propia cuenta y a la información personal que le corresponda.

Comunidad de AniMap: consulta de la información que los usuarios publiquen en reportes y avistamientos, incluyendo fotografías, características de las mascotas y ubicaciones del evento.

Administradores autorizados: acceso a funciones de gestión y moderación necesarias para el funcionamiento y seguridad del sistema.

Proveedores tecnológicos: tratamiento de los datos estrictamente necesarios para prestar los servicios contratados o configurados.

Autoridades competentes: acceso a información cuando exista una obligación legal o requerimiento válido.

Los datos personales no deberán divulgarse de forma indiscriminada.

El acceso a información de contacto de los propietarios deberá respetar las decisiones de visibilidad del usuario y los controles establecidos en el sistema.
'''),
  _LegalSection('11. Servicios y proveedores externos', '''
AniMap podrá utilizar proveedores tecnológicos para almacenamiento, infraestructura, mapas, autenticación o notificaciones.

Antes de activar servicios que impliquen el tratamiento de datos personales por terceros, se deberá identificar a los proveedores, sus funciones y las condiciones aplicables.

En caso de transferencias o transmisiones internacionales de datos, se verificarán las obligaciones legales correspondientes y se actualizará esta política cuando sea necesario.

No se compartirán datos personales con terceros para finalidades diferentes de las informadas, salvo autorización válida o excepción legal aplicable.
'''),
  _LegalSection('12. Conservación y eliminación de datos', '''
Los datos personales se conservarán durante el tiempo necesario para cumplir las finalidades autorizadas y las obligaciones legales que correspondan.

La información de una cuenta podrá mantenerse mientras esta continúe activa y sea necesaria para prestar las funcionalidades solicitadas.

Cuando el usuario solicite la eliminación de su cuenta o la supresión de información personal, se evaluará y atenderá la solicitud según las disposiciones aplicables.

La supresión podrá estar limitada cuando exista un deber legal o contractual que exija conservar determinados datos.

Las copias de seguridad y los registros técnicos deberán gestionarse mediante procedimientos de conservación y eliminación.

Periodo de vigencia de las bases de datos y calendario de eliminación: [Pendiente de definición antes de publicar la política].

Al finalizar la fase piloto del proyecto, se deberá revisar qué datos continúan siendo necesarios y cuáles deben eliminarse o anonimizarse.
'''),
  _LegalSection('13. Derechos de los titulares de datos', '''
De acuerdo con la legislación colombiana, los usuarios podrán ejercer los siguientes derechos:

• Conocer los datos personales que se encuentran almacenados sobre ellos.
• Solicitar la actualización o rectificación de información incorrecta.
• Solicitar información sobre el uso de sus datos.
• Solicitar prueba de la autorización otorgada, salvo las excepciones legales.
• Revocar la autorización cuando proceda.
• Solicitar la supresión de datos personales en los casos permitidos.
• Presentar quejas ante la Superintendencia de Industria y Comercio, cumpliendo el procedimiento legal correspondiente.
• Acceder gratuitamente a sus datos personales en los términos previstos por la ley.
'''),
  _LegalSection('14. Procedimiento para ejercer los derechos', '''
El usuario podrá presentar solicitudes relacionadas con sus datos personales a través del canal oficial de atención de AniMap.

Correo de atención: [Pendiente de confirmar].

La solicitud deberá indicar, como mínimo, el nombre del titular, un medio de contacto, una descripción clara de la petición y la información necesaria para verificar su identidad.

Cuando proceda, las consultas se atenderán dentro de los diez (10) días hábiles siguientes a su recepción, con posibilidad de ampliación de hasta cinco (5) días hábiles adicionales en las condiciones previstas por la ley.

Los reclamos se atenderán dentro de los quince (15) días hábiles contados a partir del día siguiente a su recepción, con posibilidad de ampliación de hasta ocho (8) días hábiles adicionales cuando corresponda.

Si la solicitud requiere subsanación o información adicional, se aplicará el procedimiento establecido por la legislación vigente.
'''),
  _LegalSection('15. Datos de niños, niñas y adolescentes', '''
AniMap deberá respetar especialmente los derechos y la privacidad de los niños, niñas y adolescentes.

No se solicitarán deliberadamente datos personales de menores que no sean necesarios para los objetivos del proyecto.

Si se contempla la participación o registro de menores de edad, previamente deberán definirse las condiciones legales aplicables y los mecanismos de autorización y protección reforzada.
'''),
  _LegalSection('16. Uso de información en la investigación académica', '''
AniMap se desarrolla como un proyecto de investigación aplicada.

Durante la evaluación del prototipo podrán realizarse pruebas funcionales, entrevistas y actividades de recopilación de opiniones para analizar su funcionamiento y utilidad.

La participación en entrevistas o actividades de investigación que impliquen tratamiento adicional de datos personales requerirá la información y autorización correspondientes.

Los resultados académicos deberán presentarse preferiblemente de forma agregada o anonimizada, evitando divulgar información que identifique innecesariamente a los participantes.

Los datos personales recopilados para el uso de la aplicación no serán utilizados automáticamente para investigaciones adicionales sin contar con una finalidad y habilitación legal adecuadas.
'''),
  _LegalSection('17. Modificaciones de la política de privacidad', '''
Esta política podrá actualizarse como consecuencia de cambios en el funcionamiento de AniMap, incorporación de nuevas características o modificaciones normativas.

Los cambios relevantes serán comunicados mediante los mecanismos disponibles.

Cuando las modificaciones impliquen nuevas finalidades o tratamientos que requieran autorización adicional, esta deberá obtenerse antes de realizar dichos tratamientos.
'''),
  _LegalSection('18. Vigencia', '''
La presente política entrará en vigor en la fecha que se establezca para su publicación oficial dentro de AniMap.

Versión: 1.0 — Borrador.

Fecha de entrada en vigencia: [Pendiente].

Periodo de vigencia de las bases de datos: [Pendiente de definición].
'''),
];
