# Create CSKG

## Extract individual graphs

### ATOMIC
kgtk import_atomic input/v4_atomic_all_agg.csv > tmp/kgtk_atomic.tsv 

### ConceptNet
kgtk import_conceptnet --english_only input/conceptnet-assertions-5.7.0.csv > tmp/kgtk_conceptnet.tsv

### ROGET
kgtk import_concept_pairs -i input/antonyms.txt --source RG --relation /r/Antonym > tmp/kgtk_roget_antonyms.tsv
kgtk import_concept_pairs -i input/synonyms.txt --source RG --relation /r/Synonym > tmp/kgtk_roget_synonyms.tsv

### Visual Genome
kgtk import-visualgenome -i input/visualgenome/scene_graphs.json --attr-synsets input/visualgenome/attribute_synsets.json > tmp/kgtk_visualgenome.tsv

### WordNet
kgtk import_wordnet > tmp/kgtk_wordnet.tsv

### FrameNet
kgtk import-framenet > tmp/kgtk_framenet.tsv

## Combine sources and add IDs
kgtk cat tmp/kgtk_atomic.tsv tmp/kgtk_conceptnet.tsv tmp/kgtk_roget_synonyms.tsv tmp/kgtk_roget_antonyms.tsv tmp/kgtk_framenet.tsv tmp/kgtk_wordnet.tsv tmp/kgtk_visualgenome.tsv tmp/wikidata20200504/kgtk_wikidata.tsv / sort -c 'node1,relation,node2' / add_id --id-style node1-label-node2-num / reorder_columns --columns id ... / cat --output-format tsv-unquoted > output/cskg_base.tsv

## Compact the graph
kgtk cat tmp/kgtk_atomic.tsv tmp/kgtk_conceptnet.tsv tmp/kgtk_roget_synonyms.tsv tmp/kgtk_roget_antonyms.tsv tmp/kgtk_framenet.tsv tmp/kgtk_wordnet.tsv tmp/kgtk_visualgenome.tsv tmp/wikidata20200504/kgtk_wikidata.tsv / sort -c 'node1,relation,node2' / compact --columns node1 relation node2 --presorted False / add_id --id-style node1-label-node2-num / reorder_columns --columns id ... / cat --output-format tsv-unquoted > output/cskg_compact.tsv

## Concatenate mappings
kgtk cat tmp/kgtk_atomic.tsv tmp/kgtk_conceptnet.tsv tmp/kgtk_roget_synonyms.tsv tmp/kgtk_roget_antonyms.tsv tmp/kgtk_framenet.tsv tmp/kgtk_wordnet.tsv tmp/kgtk_visualgenome.tsv tmp/wikidata20200504/kgtk_wikidata.tsv tmp/mapping_wn_wn.tsv tmp/lexical_mappings.tsv tmp/mapping_fn_cn.tsv tmp/mapping_wn_wd.tsv / sort -c 'node1,relation,node2' / compact --columns node1 relation node2  > tmp/kgtk_compact_quoted.tsv 
kgtk cat tmp/kgtk_compact_quoted.tsv --output-format tsv-unquoted / add_id --id-style node1-label-node2-num / reorder_columns --columns id ... > output/cskg_compact_with_mappings.tsv

## Concatenate CSKG with the mappings and deduplicate
kgtk connected_components -i tmp/kgtk_compact_quoted.tsv --properties mw:SameAs --cluster-name-method lowest      / lift --columns-to-lift node1 node2 --lift-suffix=      --input-file tmp/kgtk_compact_quoted.tsv     --label-file -      --label-select-value connected_component      / filter  --invert -p ';mw:SameAs;'      / compact --columns node1 relation node2 --presorted False / cat --output-format tsv-unquoted / add_id --id-style node1-label-node2-num / reorder_columns --columns id ... > output/cskg_connected.tsv

## Same, but keep the quotes
kgtk connected_components -i tmp/kgtk_compact_quoted.tsv --properties mw:SameAs --cluster-name-method lowest      / lift --columns-to-lift node1 node2 --lift-suffix=      --input-file tmp/kgtk_compact_quoted.tsv     --label-file -      --label-select-value connected_component      / filter  --invert -p ';mw:SameAs;'      / compact --columns node1 relation node2 --presorted False / add_id --id-style node1-label-node2-num / reorder_columns --columns id ... > output/cskg_connected.kgtk

# Working with CSKG

## Compute statistics
kgtk graph_statistics -i output/cskg_connected.tsv --directed --degrees --hits --pagerank --statistics-only --log summary.txt > /dev/null

## Compute embeddings
kgtk normalize -i output/cskg_connected.kgtk --columns "node1;label" "relation;label" "node2;label" / \
sort -c 2,3,4 > tmp/sorted.tsv
gzip -c tmp/sorted.tsv > output/cskg_connected_normalized.tsv.gz

kgtk text_embedding \
    --embedding-projector-metadata-path none \
    --label-properties "label" \
    --isa-properties "/r/IsA" \
    --description-properties "/r/DefinedAs" \
    --property-value "/r/Causes" "/r/UsedFor" "/r/PartOf" "/r/AtLocation" "/r/CapableOf" \
    "/r/CausesDesire" "/r/SymbolOf" "/r/MadeOf" "/r/LocatedNear" "/r/Desires" "/r/HasProperty" "/r/HasFirstSubevent" \
    "/r/HasLastSubevent" "at:xAttr" "at:xEffect" "at:xIntent" "at:xNeed" "at:xReact" "at:xWant" \
    --has-properties "" \
    -f kgtk_format \
    --output-data-format kgtk_format \
    --model bert-large-nli-cls-token \
    --save-embedding-sentence \
    -i output/cskg_connected_normalized.tsv.gz \
    -p output/cskg_connected_normalized.tsv.gz \
    > output/cskg_embedings.txt


## Compute paths
kgtk paths --max_hops 2 --path_file path_nodes.tsv -i output/cskg_connected.kgtk --statistics_only --directed > paths.tsv
