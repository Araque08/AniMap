import 'package:flutter/material.dart';

import '../../../data/users/user_service.dart';

class AdminUsersPage
    extends StatefulWidget {
  final UserAdminService? service;

  const AdminUsersPage({
    super.key,
    this.service,
  });

  @override
  State<AdminUsersPage>
  createState() =>
      _AdminUsersPageState();
}

class _AdminUsersPageState
    extends State<AdminUsersPage> {
  static const Color green =
  Color(0xFF3F9568);

  static const Color darkGreen =
  Color(0xFF2F7651);

  static const Color background =
  Color(0xFFF5F8F6);

  static const Color textPrimary =
  Color(0xFF26352E);

  static const Color textSecondary =
  Color(0xFF718078);

  late final UserAdminService
  _service =
      widget.service ??
          UserAdminService();

  List<Map<String, dynamic>>
  _users = [];

  bool _loading = true;

  String? _error;

  final TextEditingController
  _searchController =
  TextEditingController();

  String _search = '';

  String? _estado;

  String? _rol;

  @override
  void initState() {
    super.initState();

    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  /*
    ==========================================================
    CARGAR
    ==========================================================
  */

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result =
      await _service.getUsers(
        search: _search,
        estado: _estado,
        rol: _rol,
      );

      if (!mounted) return;

      setState(() {
        _users = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error =
            error.toString();
        _loading = false;
      });
    }
  }

  /*
    ==========================================================
    FORMULARIO
    ==========================================================
  */

  Future<void> _openForm({
    Map<String, dynamic>? user,
  }) async {
    final editing =
        user != null;

    final formKey =
    GlobalKey<FormState>();

    final nameController =
    TextEditingController(
      text: user?['nombre']
          ?.toString() ??
          '',
    );

    final emailController =
    TextEditingController(
      text: user?['email']
          ?.toString() ??
          '',
    );

    final phoneController =
    TextEditingController(
      text: user?['telefono']
          ?.toString() ??
          '',
    );

    final passwordController =
    TextEditingController();

    String selectedRole =
        user?['rol']
            ?.toString()
            .toUpperCase() ??
            'USUARIO';

    bool saving = false;

    final result =
    await showDialog<bool>(
      context: context,
      barrierDismissible:
      !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            Future<void> save()
            async {
              if (
              !formKey.currentState!
                  .validate()
              ) {
                return;
              }

              setDialogState(() {
                saving = true;
              });

              try {
                if (editing) {
                  await _service
                      .updateUser(
                    id: (user['id']
                    as num)
                        .toInt(),
                    nombre:
                    nameController
                        .text,
                    email:
                    emailController
                        .text,
                    telefono:
                    phoneController
                        .text,
                    rol:
                    selectedRole,
                  );
                } else {
                  await _service
                      .createUser(
                    nombre:
                    nameController
                        .text,
                    email:
                    emailController
                        .text,
                    telefono:
                    phoneController
                        .text,
                    password:
                    passwordController
                        .text,
                    rol:
                    selectedRole,
                  );
                }

                if (
                dialogContext
                    .mounted
                ) {
                  Navigator.pop(
                    dialogContext,
                    true,
                  );
                }
              } catch (error) {
                if (
                !dialogContext
                    .mounted
                ) {
                  return;
                }

                setDialogState(() {
                  saving = false;
                });

                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString(),
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              backgroundColor:
              Colors.white,
              title: Text(
                editing
                    ? 'Editar usuario'
                    : 'Crear usuario',
                style:
                const TextStyle(
                  color:
                  textPrimary,
                  fontWeight:
                  FontWeight.w800,
                ),
              ),
              content:
              SingleChildScrollView(
                child: SizedBox(
                  width: 430,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize:
                      MainAxisSize
                          .min,
                      children: [
                        TextFormField(
                          controller:
                          nameController,
                          enabled:
                          !saving,
                          decoration:
                          _inputDecoration(
                            'Nombre',
                            Icons
                                .person_outline,
                          ),
                          validator:
                              (value) {
                            if (
                            value ==
                                null ||
                                value
                                    .trim()
                                    .isEmpty
                            ) {
                              return 'Ingresa el nombre';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(
                          height: 15,
                        ),

                        TextFormField(
                          controller:
                          emailController,
                          enabled:
                          !saving,
                          keyboardType:
                          TextInputType
                              .emailAddress,
                          decoration:
                          _inputDecoration(
                            'Correo electrónico',
                            Icons
                                .email_outlined,
                          ),
                          validator:
                              (value) {
                            if (
                            value ==
                                null ||
                                !value
                                    .contains(
                                  '@',
                                )
                            ) {
                              return 'Ingresa un correo válido';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(
                          height: 15,
                        ),

                        TextFormField(
                          controller:
                          phoneController,
                          enabled:
                          !saving,
                          keyboardType:
                          TextInputType
                              .phone,
                          decoration:
                          _inputDecoration(
                            'Teléfono',
                            Icons
                                .phone_outlined,
                          ),
                        ),

                        if (!editing) ...[
                          const SizedBox(
                            height: 15,
                          ),

                          TextFormField(
                            controller:
                            passwordController,
                            enabled:
                            !saving,
                            obscureText:
                            true,
                            decoration:
                            _inputDecoration(
                              'Contraseña',
                              Icons
                                  .lock_outline,
                            ),
                            validator:
                                (value) {
                              if (
                              value ==
                                  null ||
                                  value
                                      .length <
                                      8
                              ) {
                                return 'Mínimo 8 caracteres';
                              }

                              return null;
                            },
                          ),
                        ],

                        const SizedBox(
                          height: 15,
                        ),

                        DropdownButtonFormField<
                            String>(
                          initialValue:
                          selectedRole,
                          decoration:
                          _inputDecoration(
                            'Rol',
                            Icons
                                .admin_panel_settings_outlined,
                          ),
                          items:
                          const [
                            DropdownMenuItem(
                              value:
                              'USUARIO',
                              child:
                              Text(
                                'Usuario',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                              'ADMINISTRADOR',
                              child:
                              Text(
                                'Administrador',
                              ),
                            ),
                          ],
                          onChanged:
                          saving
                              ? null
                              : (value) {
                            if (
                            value ==
                                null
                            ) {
                              return;
                            }

                            setDialogState(
                                  () {
                                selectedRole =
                                    value;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                  saving
                      ? null
                      : () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                  const Text(
                    'Cancelar',
                  ),
                ),

                FilledButton(
                  style:
                  FilledButton.styleFrom(
                    backgroundColor:
                    green,
                  ),
                  onPressed:
                  saving
                      ? null
                      : save,
                  child: saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth:
                      2,
                      color:
                      Colors.white,
                    ),
                  )
                      : Text(
                    editing
                        ? 'Guardar'
                        : 'Crear',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();

    if (result == true) {
      await _load();
    }
  }

  /*
    ==========================================================
    CAMBIAR ESTADO
    ==========================================================
  */

  Future<void> _changeStatus(
      Map<String, dynamic> user,
      ) async {
    final current =
    user['estado_cuenta']
        ?.toString()
        .toUpperCase();

    final next =
    current == 'ACTIVO'
        ? 'SUSPENDIDO'
        : 'ACTIVO';

    try {
      await _service
          .setUserStatus(
        (user['id'] as num)
            .toInt(),
        next,
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content:
          Text(
            error.toString(),
          ),
        ),
      );
    }
  }

  /*
    ==========================================================
    ELIMINAR
    ==========================================================
  */

  Future<void> _deleteUser(
      Map<String, dynamic> user,
      ) async {
    final confirmed =
    await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title:
            const Text(
              'Eliminar usuario',
            ),
            content: Text(
              '¿Deseas eliminar la cuenta de ${user['nombre']}?\n\n'
                  'La cuenta quedará inactiva y no podrá iniciar sesión.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                      context,
                      false,
                    ),
                child:
                const Text(
                  'Cancelar',
                ),
              ),
              FilledButton(
                style:
                FilledButton.styleFrom(
                  backgroundColor:
                  const Color(
                    0xFFB95050,
                  ),
                ),
                onPressed: () =>
                    Navigator.pop(
                      context,
                      true,
                    ),
                child:
                const Text(
                  'Eliminar',
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteUser(
        (user['id'] as num)
            .toInt(),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content:
          Text(
            error.toString(),
          ),
        ),
      );
    }
  }

  /*
    ==========================================================
    INPUT
    ==========================================================
  */

  static InputDecoration
  _inputDecoration(
      String label,
      IconData icon,
      ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: green,
      ),
      filled: true,
      fillColor:
      Colors.white,
      border:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          14,
        ),
      ),
    );
  }

  /*
    ==========================================================
    UI
    ==========================================================
  */

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      background,

      appBar: AppBar(
        backgroundColor:
        background,
        surfaceTintColor:
        background,
        foregroundColor:
        textPrimary,
        elevation: 0,
        title:
        const Text(
          'Gestión de usuarios',
          style:
          TextStyle(
            fontWeight:
            FontWeight.w800,
          ),
        ),
      ),

      floatingActionButton:
      FloatingActionButton.extended(
        backgroundColor:
        green,
        foregroundColor:
        Colors.white,
        onPressed: () =>
            _openForm(),
        icon:
        const Icon(
          Icons.person_add_alt_1,
        ),
        label:
        const Text(
          'Nuevo usuario',
        ),
      ),

      body:
      RefreshIndicator(
        color: green,
        onRefresh: _load,
        child:
        ListView(
          padding:
          const EdgeInsets
              .fromLTRB(
            20,
            10,
            20,
            100,
          ),
          children: [
            /*
              ENCABEZADO
            */

            Container(
              padding:
              const EdgeInsets
                  .all(
                22,
              ),
              decoration:
              BoxDecoration(
                gradient:
                const LinearGradient(
                  colors: [
                    green,
                    darkGreen,
                  ],
                ),
                borderRadius:
                BorderRadius
                    .circular(
                  24,
                ),
              ),
              child:
              const Row(
                children: [
                  Icon(
                    Icons
                        .people_alt_outlined,
                    color:
                    Colors.white,
                    size: 38,
                  ),
                  SizedBox(
                    width: 16,
                  ),
                  Expanded(
                    child:
                    Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          'Usuarios de AniMap',
                          style:
                          TextStyle(
                            color:
                            Colors.white,
                            fontSize:
                            20,
                            fontWeight:
                            FontWeight
                                .w800,
                          ),
                        ),
                        SizedBox(
                          height: 5,
                        ),
                        Text(
                          'Consulta, crea y administra las cuentas registradas.',
                          style:
                          TextStyle(
                            color:
                            Color(
                              0xFFE7F3EC,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 22,
            ),

            /*
              BUSCADOR
            */

            TextField(
              controller:
              _searchController,
              decoration:
              InputDecoration(
                hintText:
                'Buscar por nombre, correo o teléfono',
                prefixIcon:
                const Icon(
                  Icons.search,
                ),
                suffixIcon:
                _search.isEmpty
                    ? null
                    : IconButton(
                  onPressed:
                      () {
                    _searchController
                        .clear();

                    setState(
                          () {
                        _search =
                        '';
                      },
                    );

                    _load();
                  },
                  icon:
                  const Icon(
                    Icons.close,
                  ),
                ),
                filled: true,
                fillColor:
                Colors.white,
                border:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius
                      .circular(
                    16,
                  ),
                  borderSide:
                  BorderSide
                      .none,
                ),
              ),
              onSubmitted:
                  (value) {
                _search =
                    value.trim();

                _load();
              },
            ),

            const SizedBox(
              height: 14,
            ),

            /*
              FILTROS
            */

            Row(
              children: [
                Expanded(
                  child:
                  DropdownButtonFormField<
                      String?>(
                    initialValue:
                    _estado,
                    decoration:
                    const InputDecoration(
                      labelText:
                      'Estado',
                      filled:
                      true,
                      fillColor:
                      Colors.white,
                    ),
                    items:
                    const [
                      DropdownMenuItem<
                          String?>(
                        value:
                        null,
                        child:
                        Text(
                          'Todos',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                        'ACTIVO',
                        child:
                        Text(
                          'Activo',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                        'SUSPENDIDO',
                        child:
                        Text(
                          'Suspendido',
                        ),
                      ),
                    ],
                    onChanged:
                        (value) {
                      setState(
                            () {
                          _estado =
                              value;
                        },
                      );

                      _load();
                    },
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child:
                  DropdownButtonFormField<
                      String?>(
                    initialValue:
                    _rol,
                    decoration:
                    const InputDecoration(
                      labelText:
                      'Rol',
                      filled:
                      true,
                      fillColor:
                      Colors.white,
                    ),
                    items:
                    const [
                      DropdownMenuItem<
                          String?>(
                        value:
                        null,
                        child:
                        Text(
                          'Todos',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                        'USUARIO',
                        child:
                        Text(
                          'Usuario',
                        ),
                      ),
                      DropdownMenuItem(
                        value:
                        'ADMINISTRADOR',
                        child:
                        Text(
                          'Administrador',
                        ),
                      ),
                    ],
                    onChanged:
                        (value) {
                      setState(
                            () {
                          _rol =
                              value;
                        },
                      );

                      _load();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 22,
            ),

            if (_loading)
              const Padding(
                padding:
                EdgeInsets.all(
                  40,
                ),
                child:
                Center(
                  child:
                  CircularProgressIndicator(
                    color:
                    green,
                  ),
                ),
              )
            else if (
            _error != null
            )
              _ErrorCard(
                message:
                _error!,
                retry:
                _load,
              )
            else if (
              _users.isEmpty
              )
                const Padding(
                  padding:
                  EdgeInsets.all(
                    35,
                  ),
                  child:
                  Center(
                    child:
                    Text(
                      'No se encontraron usuarios.',
                      style:
                      TextStyle(
                        color:
                        textSecondary,
                      ),
                    ),
                  ),
                )
              else
                ..._users.map(
                  _buildUserCard,
                ),
          ],
        ),
      ),
    );
  }

  /*
    ==========================================================
    TARJETA
    ==========================================================
  */

  Widget _buildUserCard(
      Map<String, dynamic> user,
      ) {
    final active =
        user['estado_cuenta']
            ?.toString()
            .toUpperCase() ==
            'ACTIVO';

    final verified =
        user['is_verified'] ==
            true;

    final role =
        user['rol']
            ?.toString() ??
            'Sin rol';

    return Container(
      margin:
      const EdgeInsets.only(
        bottom: 13,
      ),
      padding:
      const EdgeInsets.all(
        16,
      ),
      decoration:
      BoxDecoration(
        color:
        Colors.white,
        borderRadius:
        BorderRadius.circular(
          19,
        ),
        border:
        Border.all(
          color:
          const Color(
            0xFFE1E9E5,
          ),
        ),
      ),
      child:
      Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                active
                    ? const Color(
                  0xFFEAF5EF,
                )
                    : const Color(
                  0xFFF0F1F1,
                ),
                child:
                Icon(
                  Icons
                      .person_outline,
                  color:
                  active
                      ? green
                      : Colors
                      .grey,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child:
                Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      user['nombre']
                          ?.toString() ??
                          'Usuario',
                      style:
                      const TextStyle(
                        color:
                        textPrimary,
                        fontSize:
                        16,
                        fontWeight:
                        FontWeight
                            .w800,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      user['email']
                          ?.toString() ??
                          '',
                      style:
                      const TextStyle(
                        color:
                        textSecondary,
                        fontSize:
                        13,
                      ),
                    ),
                  ],
                ),
              ),

              PopupMenuButton<
                  String>(
                onSelected:
                    (value) {
                  switch (
                  value) {
                    case 'edit':
                      _openForm(
                        user:
                        user,
                      );
                      break;

                    case 'status':
                      _changeStatus(
                        user,
                      );
                      break;

                    case 'delete':
                      _deleteUser(
                        user,
                      );
                      break;
                  }
                },
                itemBuilder:
                    (context) => [
                  const PopupMenuItem(
                    value:
                    'edit',
                    child:
                    Text(
                      'Editar',
                    ),
                  ),
                  PopupMenuItem(
                    value:
                    'status',
                    child:
                    Text(
                      active
                          ? 'Suspender'
                          : 'Activar',
                    ),
                  ),
                  const PopupMenuItem(
                    value:
                    'delete',
                    child:
                    Text(
                      'Eliminar',
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(
            height: 13,
          ),

          Row(
            children: [
              _Badge(
                text:
                role,
                background:
                const Color(
                  0xFFEAF1F8,
                ),
                foreground:
                const Color(
                  0xFF4779A8,
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              _Badge(
                text:
                active
                    ? 'ACTIVO'
                    : 'INACTIVO',
                background:
                active
                    ? const Color(
                  0xFFEAF5EF,
                )
                    : const Color(
                  0xFFFFEEEE,
                ),
                foreground:
                active
                    ? green
                    : const Color(
                  0xFFB95050,
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              if (verified)
                const _Badge(
                  text:
                  'VERIFICADO',
                  background:
                  Color(
                    0xFFF1F4F2,
                  ),
                  foreground:
                  Color(
                    0xFF617169,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/*
  ============================================================
  BADGE
  ============================================================
*/

class _Badge
    extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration:
      BoxDecoration(
        color:
        background,
        borderRadius:
        BorderRadius.circular(
          20,
        ),
      ),
      child:
      Text(
        text,
        style:
        TextStyle(
          color:
          foreground,
          fontSize:
          10,
          fontWeight:
          FontWeight.w800,
        ),
      ),
    );
  }
}

/*
  ============================================================
  ERROR
  ============================================================
*/

class _ErrorCard
    extends StatelessWidget {
  final String message;
  final VoidCallback retry;

  const _ErrorCard({
    required this.message,
    required this.retry,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Center(
      child:
      Column(
        children: [
          const Icon(
            Icons
                .error_outline,
            color:
            Color(
              0xFFB95050,
            ),
            size:
            45,
          ),

          const SizedBox(
            height: 12,
          ),

          Text(
            message,
            textAlign:
            TextAlign.center,
          ),

          const SizedBox(
            height: 12,
          ),

          FilledButton(
            onPressed:
            retry,
            child:
            const Text(
              'Reintentar',
            ),
          ),
        ],
      ),
    );
  }
}