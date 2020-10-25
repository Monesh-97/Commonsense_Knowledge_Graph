import click
from pathlib import Path
import shutil
from config_dist import get_config
import json
import h5py
import os
from torchbiggraph.distributed import init_process_group
from torchbiggraph.config import parse_config
from torchbiggraph.converters.importers import TSVEdgelistReader, convert_input_data
from torchbiggraph.train import train
from torchbiggraph.util import SubprocessInitializer, setup_logging

# Initializing libiomp5.dylib, but found libomp.dylib already initialized.
# solution: Allow repeat loading dynamic link library 
os.environ["KMP_DUPLICATE_LIB_OK"]="TRUE"

def tsv_process(tsv_file,output_file): 
    # if already exists, then delete
    # if Path(output_file).exists:
    #     Path(output_file).unlink()

    output = open(output_file,'w')
    count = 0
    with open(tsv_file) as f:
        for line in f:
            content = line.split('\t')[:3]
            if content[1]!='relation': # ignore the first time
                output.write(content[0]+'\t')
                output.write(content[1]+'\t')
                output.write(content[2]+'\n')
                count+=1
            # if count>1000:
            #     break
    output.close()

@click.command()
@click.option('-i','--input',help='Input KGTK file',required=True, metavar='')
@click.option('-o','--output',help='Output directory', required=True, metavar='')
@click.option('-d','--dimension',help='Dimension of the real space \
	the embedding live in [Default: 10]',default=10, type=int,metavar='')
@click.option('-s','--init_scale',help='Generating the initial \
	embedding with this standard deviation [Default: 0.01]',type=float,default=0.01, metavar='')
@click.option('-c','--comparator',help='Comparator types [Default:dot] Choice: dot | cos | l2 | squared_l2 \
	',default='dot',type=click.Choice(['dot','cos','l2','squared_l2']),metavar='')
@click.option('-b','--bias',help='Whether use the bias choice [Default: False]',type=bool,default=False,metavar='')
@click.option('-e','--num_epochs',help='Training epoch numbers[Default: 50]',type=int,default=50,metavar='')
@click.option('-ge','--global_emb',help='Whether use global embedding [Default: False]',type=bool,default=False,metavar='')
@click.option('-lf','--loss_fn',help='Type of loss function [Default: logistic] \
	Choice: ranking | logistic | softmax ',default='logistic',type=click.Choice(['ranking','logistic','softmax']),metavar='')
@click.option('-lr','--learning_rate',help='Learning rate [Default: 0.1]',type=float,default=0.1,metavar='')
@click.option('-rc','--regularization_coef',help='Regularization coefficient [Default: 1e-3]',type=float,default=1e-3,metavar='')
@click.option('-nn','--num_uniform_negs',help='Negative sampling number [Default: 1000]',type=int,default=1000,metavar='')
@click.option('-dr','--dynamic_relaitons',help='Whether use dynamic relations (when graphs with a \
	large number of relations)[Default: True]',type=bool,default=True,metavar='')
@click.option('-ef','--eval_fraction',help='Fraction of edges withheld from training and used \
	to track evaluation metrics during training.[Default: 0.0]',type=float,default=0.0,metavar='')
def main(**args):
    """
    Parameters setting and graph embedding
    """

    input_path = Path(args['input'])
    output_path = Path(args['output'])

    #prepare  the graph file
    try:  
        tmp_tsv_path = Path('tmp') / input_path.name
        shutil.rmtree(tmp_tsv)
    except:pass
    tsv_process(input_path,tmp_tsv_path)  


    # *********************************************
    # 1. DEFINE CONFIG
    # *********************************************
    edge_paths = [str(output_path / 'edges_partitioned')]
    checkpoint_path = str(output_path/'model')

    entities= {"all": {"num_partitions": 4}}  #######......
    relations=[
        {
            "name": "all_edges",
            "lhs": "all",
            "rhs": "all",
            "operator": "complex_diagonal",
        }
    ]

    raw_config = get_config(entity_path=output_path,edge_paths=edge_paths,checkpoint_path=checkpoint_path,
        entities_structure=entities,relation_structure=relations,dynamic_relations=args['dynamic_relaitons'],
        dimension=args['dimension'],global_emb=args['global_emb'],comparator=args['comparator'],              
        init_scale=args['init_scale'],bias=args['bias'],num_epochs=args['num_epochs'],num_uniform_negs=args['num_uniform_negs'],
        loss_fn=args['loss_fn'],lr=args['learning_rate'],regularization_coef=args['regularization_coef'],
        eval_fraction=args['eval_fraction'])

    # **************************************************
    # 2. TRANSFORM GRAPH TO A BIGGRAPH-FRIENDLY FORMAT
    # **************************************************
    setup_logging()
    config = parse_config(raw_config)
    subprocess_init = SubprocessInitializer()
    input_edge_paths = [tmp_tsv_path] 

    convert_input_data(
        config.entities,
        config.relations,
        config.entity_path,
        config.edge_paths,
        input_edge_paths,
        TSVEdgelistReader(lhs_col=0, rel_col=1, rhs_col=2),
        dynamic_relations=config.dynamic_relations,
    )
    # ************************************************
    # 3. TRAIN THE EMBEDDINGS
    #*************************************************
    train(config, subprocess_init=subprocess_init,rank=0)


if __name__ == "__main__":
    main()