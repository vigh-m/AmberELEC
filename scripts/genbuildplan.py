#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019-present Team LibreELEC (https://libreelec.tv)

import sys, os, codecs, json, argparse, re

ROOT_PKG = "__root__"

class LibreELEC_Package:
    def __init__(self, name, section):
        self.name = name
        self.section = section
        self.deps = {"bootstrap": [],
                     "init":      [],
                     "host":      [],
                     "target":    []}
        self.wants = set()
        self.wantedby = set()

    def __repr__(self):
        parts = [
            f"{'name':<9}: {self.name}",
            f"{'section':<9}: {self.section}"
        ]
        parts.extend(f"{t:<9}: {self.deps[t]}" for t in self.deps)
        parts.extend([
            f"{'NEEDS':<9}: {self.wants}",
            f"{'WANTED BY':<9}: {self.wantedby}"
        ])
        return "\n".join(parts)

    def addDependencies(self, target, packages):
        for d in " ".join(packages.split()).split():
            self.deps[target].append(d)
            name = d.partition(":")[0]
            if name != self.name:
                self.wants.add(name)

    def delDependency(self, target, package):
        if package in self.deps[target]:
            self.deps[target].remove(package)
            name = package.partition(":")[0]
            self.wants.discard(name)

    def addReference(self, package):
        name = package.partition(":")[0]
        self.wantedby.add(name)

    def delReference(self, package):
        name = package.partition(":")[0]
        self.wantedby.discard(name)

    def isReferenced(self):
        return bool(self.wants)

    def isWanted(self):
        return bool(self.wantedby)

    def references(self, package):
        return package in self.wants

# Reference material:
# https://www.electricmonk.nl/docs/dependency_resolving_algorithm/dependency_resolving_algorithm.html
class Node:
    def __init__(self, name, target, section):
        self.name = name
        self.target = target
        self.section = section
        self.fqname = f"{name}:{target}"
        self.edges = []

    def appendEdges(self, node):
        if node not in self.edges:
            self.edges.append(node)
        for e in node.edges:
            if e not in self.edges:
                self.edges.append(e)

    def satisfies(self, node):
        for e in node.edges:
            if e not in self.edges:
                return False
        return True

    def __repr__(self):
        base = "\n".join([
            f"{'name':<9}: {self.name}",
            f"{'target':<9}: {self.target}",
            f"{'fqname':<9}: {self.fqname}",
            f"{'common':<9}: {self.commonName()}",
            f"{'section':<9}: {self.section}"
        ])
        edges = "\n".join(f"EDGE: {e.fqname}" for e in self.edges)
        return f"{base}\n{edges}" if edges else base

    def commonName(self):
        return self.name if self.target == "target" else f"{self.name}:{self.target}"

    def addEdge(self, node):
        if node not in self.edges:
            self.edges.append(node)

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def loadPackages():
    jdata = json.loads(f"[{sys.stdin.read().replace(chr(10),'')[:-1]}]")

    map = {}

    for pkg in jdata:
        if pkg["hierarchy"] == "global":
            map[pkg["name"]] = initPackage(pkg)

    for pkg in jdata:
        if pkg["hierarchy"] == "local":
            map[pkg["name"]] = initPackage(pkg)

    return map

def initPackage(package):
    pkg = LibreELEC_Package(package["name"], package["section"])

    for target in ["bootstrap", "init", "host", "target"]:
        pkg.addDependencies(target, package[target])

    return pkg

def split_package(name):
    parts = name.partition(":")
    pn = parts[0]
    pt = parts[2] if parts[2] else "target"
    return (pn, pt)

def get_packages_by_target(target, list):
    newlist = []

    for p in list:
        (pn, pt) = split_package(p)
        if target in ["target", "init"] and pt in ["target", "init"]:
            newlist.append(p)
        elif target in ["bootstrap", "host"] and pt in ["bootstrap", "host"]:
            newlist.append(p)

    return newlist

def dep_resolve(node, resolved, unresolved):
    unresolved.append(node)

    for edge in node.edges:
        if edge not in resolved:
            if edge in unresolved:
                raise Exception(
                    f"Circular reference detected: {node.fqname} -> {edge.commonName()}\n"
                    f"Remove {edge.commonName()} from {node.name} package.mk::PKG_DEPENDS_{node.target.upper()}"
                )
            dep_resolve(edge, resolved, unresolved)

    if node not in resolved:
        resolved.append(node)

    unresolved.remove(node)

def get_build_steps(args, nodes):
    resolved = []
    unresolved = []

    install = True if "image" in args.build else False

    for pkgname in [x for x in args.build if x]:
        if pkgname.find(":") == -1:
            pkgname = f"{pkgname}:target"

        if pkgname in nodes:
            dep_resolve(nodes[pkgname], resolved, unresolved)

    if unresolved != []:
        eprint("The following dependencies have not been resolved:")
        for dep in unresolved:
            eprint(f"  {dep}")
        raise("Unresolved references")

    for pkg in resolved:
        task = "build" if pkg.fqname.endswith(":host") or pkg.fqname.endswith(":init") or not install else "install"
        yield(task, pkg.fqname)

def processPackages(args, packages):
    pkg = {
            "name": ROOT_PKG,
            "section": "virtual",
            "hierarchy": "global",
            "bootstrap": "",
            "init": "",
            "host": " ".join(get_packages_by_target("host", args.build)),
            "target": " ".join(get_packages_by_target("target", args.build))
          }

    packages[pkg["name"]] = initPackage(pkg)

    for pkgname in packages:
        for opkgname in packages:
            opkg = packages[opkgname]
            if opkg.references(pkgname):
                if pkgname in packages:
                    packages[pkgname].addReference(opkgname)

    while True:
        changed = False
        for pkgname in packages:
            pkg = packages[pkgname]
            if pkg.isWanted():
                for opkgname in list(pkg.wantedby):
                    if opkgname != ROOT_PKG:
                        if not packages[opkgname].isWanted():
                            pkg.delReference(opkgname)
                            changed = True
        if not changed:
            break

    needed_map = {}
    for pkgname in packages:
        pkg = packages[pkgname]
        if pkg.isWanted() or pkgname == ROOT_PKG:
            needed_map[pkgname] = pkg

    if not args.ignore_invalid:
        for pkgname in needed_map:
            pkg = needed_map[pkgname]
            for t in pkg.deps:
                for d in pkg.deps[t]:
                    if split_package(d)[0] not in needed_map:
                        msg = f'Invalid package reference: dependency {d} in package {pkgname}::PKG_DEPENDS_{t.upper()} is not valid'
                        if args.warn_invalid:
                            eprint(f"WARNING: {msg}")
                        else:
                            raise Exception(msg)

    node_map = {}

    for pkgname in needed_map:
        pkg = needed_map[pkgname]
        for target in pkg.deps:
            if pkg.deps[target]:
                node = Node(pkgname, target, pkg.section)
                node_map[node.fqname] = node

    for pkgname in needed_map:
        pkg = needed_map[pkgname]
        for target in pkg.deps:
            for dep in pkg.deps[target]:
                dfq = dep if dep.find(":") != -1 else f"{dep}:target"
                if dfq not in node_map:
                    (dfq_p, dfq_t) = split_package(dfq)
                    if dfq_p in packages:
                        dpkg = packages[dfq_p]
                        node_map[dfq] = Node(dfq_p, dfq_t, dpkg.section)
                    elif not args.ignore_invalid:
                        raise Exception(f"Invalid package! Package {dfq_p} cannot be found for this PROJECT/DEVICE/ARCH")

    for name in node_map:
        node = node_map[name]
        if node.name not in needed_map:
            if args.warn_invalid:
                continue
            else:
                raise Exception(f"Invalid package! Package {node.name} cannot be found for this PROJECT/DEVICE/ARCH")
        for dep in needed_map[node.name].deps[node.target]:
            dfq = dep if dep.find(":") != -1 else f"{dep}:target"
            if dfq in node_map:
                node.addEdge(node_map[dfq])

    return node_map

#---------------------------------------------
parser = argparse.ArgumentParser(description="Generate package dependency list for the requested build/install packages.    \
                                              Package data will be read from stdin in JSON format.", \
                                 formatter_class=lambda prog: argparse.HelpFormatter(prog,max_help_position=25,width=90))

parser.add_argument("-b", "--build", nargs="+", metavar="PACKAGE", required=True, \
                    help="Space-separated list of build trigger packages, either for host or target. Required property - specify at least one package.")

parser.add_argument("--warn-invalid", action="store_true", default=False, \
                    help="Warn about invalid/missing dependency packages, perhaps excluded by a PKG_ARCH incompatibility. Default is to abort.")

parser.add_argument("--ignore-invalid", action="store_true", default=False, \
                    help="Ignore invalid packages.")

group = parser.add_mutually_exclusive_group()
group.add_argument("--show-wants", action="store_true", \
                    help="Output \"wants\" dependencies for each step.")
group.add_argument("--hide-wants", action="store_false", dest="show_wants", default=True, \
                    help="Disable --show-wants. This is the default.")

parser.add_argument("--no-reorder", action="store_true", default=True, \
                    help="Ignored, kept for compatibility.")

parser.add_argument("--with-json", metavar="FILE", \
                    help="File into which JSON formatted plan will be written.")

args = parser.parse_args()

ALL_PACKAGES = loadPackages()

loaded = len(ALL_PACKAGES)

REQUIRED_PKGS = processPackages(args, ALL_PACKAGES)

steps = [step for step in get_build_steps(args, REQUIRED_PKGS)]

eprint(f"Packages loaded : {loaded}")
eprint(f"Build trigger(s): {len(args.build)} [{' '.join(args.build)}]")
eprint(f"Package steps   : {len(steps)}")
eprint("")

if args.with_json:
    plan = []
    for step in steps:
        (pkg_name, target) = split_package(step[1])
        plan.append({"task": step[0],
                     "name": step[1],
                     "section": ALL_PACKAGES[pkg_name].section if pkg_name in ALL_PACKAGES else "unknown",
                     "wants": [d.fqname for d in REQUIRED_PKGS[step[1]].edges]})

    with open(args.with_json, "w") as out:
        print(json.dumps(plan, indent=2, sort_keys=False), file=out)

if args.show_wants:
    for step in steps:
        node = (REQUIRED_PKGS[step[1]])
        wants = [edge.fqname for edge in node.edges]
        print(f"{step[0]:<7} {step[1].replace(':target',''):<25} (wants: {', '.join(wants).replace(':target','')})")
else:
    for step in steps:
        print(f"{step[0]:<7} {step[1].replace(':target','')}")
