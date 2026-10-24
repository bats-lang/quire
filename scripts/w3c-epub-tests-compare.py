#!/usr/bin/env python3
"""Where two survey runs of scripts/w3c-epub-tests-survey.mjs disagree (quire#827).

usage: scripts/w3c-epub-tests-compare.py <survey dir of one project> <survey dir of the other>

Compares what the reader showed (the places visited, their text, images,
links and mathml/svg counts, the contents panel and the errors), not the
geometry, which differs with the window by design. Prints each test whose
run differs, with the fields that differ, and the number of tests.
"""
import glob
import json
import os
import sys


def collapse(places):
    """Consecutive identical places are one place (the end of a book is visited again)"""
    kept = []
    for place in places:
        if not kept or kept[-1] != place:
            kept.append(place)
    return kept


FIELDS = ('text', 'images', 'links', 'mathml', 'svg')


def view(run):
    places = collapse([
        (chapter['text'], [(image['w'], image['h']) for image in chapter['imgs']],
         [link['href'] for link in chapter['links']], chapter['mathml'], chapter['svg'])
        for chapter in run['chapters']])
    return {'opened': run.get('opened'), 'places': places, 'contents': run.get('contents'),
            'errors': [error for error in run['errors'] if 'survey' in error]}


def main(first_dir, second_dir):
    differing = 0
    files = sorted(glob.glob(first_dir + '/*.json'))
    for path in files:
        name = os.path.basename(path)
        first = view(json.load(open(path)))
        second = view(json.load(open(os.path.join(second_dir, name))))
        if first == second:
            continue
        fields = [key for key in ('opened', 'contents', 'errors') if first[key] != second[key]]
        if len(first['places']) != len(second['places']):
            fields.append('places')
        for one, other in zip(first['places'], second['places']):
            fields += [FIELDS[i] for i in range(len(FIELDS)) if one[i] != other[i] and FIELDS[i] not in fields]
        differing += 1
        print(name[:-5], fields)
    print(differing, 'differ of', len(files))


if __name__ == '__main__':
    main(*sys.argv[1:3])
