************
Other Topics
************

This section describes some details of Dune for advanced users.

.. _variables-for-artifacts:

Variables for Artifacts
-----------------------

For specific situations where one needs to refer to individual compilation
artifacts, special variables (see :doc:`concepts/variables`) are provided, so
the user doesn't need to be aware of the particular naming conventions or
directory layout implemented by Dune.

These variables can appear wherever a :doc:`concepts/dependency-spec` is
expected and also inside :doc:`concepts/actions`. When used inside
:doc:`concepts/actions`, they implicitly declare a dependency on the
corresponding artifact.

The variables have the form ``%{<ext>:<path>}``, where ``<path>`` is
interpreted relative to the current directory:

- ``cmo:<path>``, ``cmx:<path>``, and ``cmi:<path>`` expand to the corresponding
  artifact's path for the module specified by ``<path>``. The basename of
  ``<path>`` should be the name of a module as specified in a ``(modules)``
  field.

- ``cma:<path>`` and ``cmxa:<path>`` expands to the corresponding 
  artifact's path for the library specified by ``<path>``. The basename of ``<path>``
  should be the name of the library as specified in the ``(name)`` field of a
  ``library`` stanza (*not* its public name).

In each case, the expansion of the variable is a path pointing inside the build
context (i.e., ``_build/<context>``).

Building an Ad Hoc ``.cmxs``
----------------------------

In the model exposed by Dune, a ``.cmxs`` target is created for each
library. However, the ``.cmxs`` format itself is more flexible and is
capable to containing arbitrary ``.cmxa`` and ``.cmx`` files.

For the specific cases where this extra flexibility is needed, one can use
:ref:`variables-for-artifacts` to write explicit rules to build ``.cmxs`` files
not associated to any library.

Below is an example where we build ``my.cmxs`` containing ``foo.cmxa`` and
``d.cmx``. Note how we use a :ref:`library` stanza to set up the compilation of
``d.cmx``.

.. code:: dune

    (library
     (name foo)
     (modules a b c))

    (library
     (name dummy)
     (modules d))

    (rule
     (targets my.cmxs)
     (action (run %{ocamlopt} -shared -o %{targets} %{cmxa:foo} %{cmx:d})))
