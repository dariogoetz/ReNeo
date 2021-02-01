module composer;

import std.stdio;
import std.utf;
import std.regex;
import std.algorithm;
import std.conv;
import std.file;

import squire;

const auto COMPOSE_REGEX = regex(`^(<[a-zA-Z0-9_]+>(?: <[a-zA-Z0-9_]+>)+)\s*:\s*"(.*)"`);

struct ComposeNode {
    uint keysym;
    ComposeNode *prev;
    ComposeNode *[] next;
    wstring result;
}

ComposeNode composeRoot;

bool active;
ComposeNode *currentNode;

enum ComposeResultType {
    PASS,
    EAT,
    FINISH,
    ABORT
}

struct ComposeResult {
    ComposeResultType type;
    wstring result;
}

void initCompose() {
    // TODO: determine based on executable location
    string composeDir = "compose";
    foreach (dirEntry; dirEntries(composeDir, "*.module", SpanMode.shallow)) {
        if (dirEntry.isFile) {
            string fname = dirEntry.name;
            writeln("Loading compose module ", fname);
            loadModule(fname);
        }
    }
}

void loadModule(string fname) {
    File f = File(fname, "r");
	while(!f.eof()) {
		string l = f.readln();
        if (auto m = matchFirst(l, COMPOSE_REGEX)) {
            auto keysyms = split(m[1], regex(" ")).map!(s => parseKeysym(s[1 .. s.length-1]));
            string result = m[2];

            auto currentNode = &composeRoot;

            foreach (keysym; keysyms) {
                ComposeNode *next;
                bool foundNext;

                foreach (nextIter; currentNode.next) {
                    if (nextIter.keysym == keysym) {
                        foundNext = true;
                        next = nextIter;
                        break;
                    }
                }

                if (!foundNext) {
                    next = new ComposeNode(keysym, currentNode, [], ""w);
                    currentNode.next ~= next;
                }

                currentNode = next;
            }

            currentNode.result = to!(wstring)(result);
        }
    }
}

ComposeResult compose(NeoKey nk) nothrow {
    if (!active) {
        foreach (startNode; composeRoot.next) {
            if (startNode.keysym == nk.keysym) {
                active = true;
                currentNode = &composeRoot;
                //printf("Started compose\n");
                break;
            }
        }

        if (!active) {
            return ComposeResult(ComposeResultType.PASS, ""w);
        }
    }

    if (active) {
        ComposeNode *next;
        bool foundNext;

        //printf("compose %x\n", nk.keysym);

        foreach (nextIter; currentNode.next) {
            if (nextIter.keysym == nk.keysym) {
                foundNext = true;
                next = nextIter;
                break;
            }
        }

        if (foundNext) {
            if (next.next.length == 0) {
                // this was the final key
                active = false;
                //printf("Finished compose\n");
                return ComposeResult(ComposeResultType.FINISH, next.result);
            } else {
                currentNode = next;
                // printf("possible next: ", nk.keysym);
                // foreach (nextIter; currentNode.next) {
                //     printf("%x ", nextIter.keysym);
                // }
                // printf("\n");
                return ComposeResult(ComposeResultType.EAT, ""w);
            }
        } else {
            active = false;
            //printf("Aborted compose\n");
            return ComposeResult(ComposeResultType.ABORT, ""w);
        }
    }
    
    return ComposeResult(ComposeResultType.PASS, ""w);
}